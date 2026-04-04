//
//  FFmpegWrapper.mm
//  PS5-media-manager
//
//  Created by 赵亦涵 on 2026/1/10.
//
//  Copyright © 2026 赵亦涵.
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU Lesser General Public License as published by
//  the Free Software Foundation; either version 2.1 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU Lesser General Public License for more details.
//
//  You should have received a copy of the GNU Lesser General Public License
//  along with this program. If not, see <http://www.gnu.org/licenses/>.
//

#import "FFmpegWrapper.h"

static NSDate *ExtractTimestampDateFromFileName(NSString *fileName) {
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(\\d{14})" options:0 error:&error];
    if (error != nil) {
        return nil;
    }

    NSTextCheckingResult *match = [regex firstMatchInString:fileName options:0 range:NSMakeRange(0, fileName.length)];
    if (match == nil || match.numberOfRanges < 2) {
        return nil;
    }

    NSString *timestamp = [fileName substringWithRange:[match rangeAtIndex:1]];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone localTimeZone];
    formatter.dateFormat = @"yyyyMMddHHmmss";
    return [formatter dateFromString:timestamp];
}

static void SynchronizeFileDatesForPath(NSString *path) {
    NSDate *timestampDate = ExtractTimestampDateFromFileName([path lastPathComponent]);
    if (timestampDate == nil) {
        return;
    }

    NSDictionary<NSFileAttributeKey, id> *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSDate *currentModificationDate = attributes[NSFileModificationDate];
    NSDate *currentCreationDate = attributes[NSFileCreationDate];
    BOOL modificationMatches = currentModificationDate != nil && fabs([currentModificationDate timeIntervalSinceDate:timestampDate]) < 1.0;
    BOOL creationMatches = currentCreationDate != nil && fabs([currentCreationDate timeIntervalSinceDate:timestampDate]) < 1.0;
    if (modificationMatches && creationMatches) {
        return;
    }

    NSError *error = nil;
    BOOL updated = NO;
    if (!modificationMatches) {
        updated = [[NSFileManager defaultManager] setAttributes:@{
            NSFileModificationDate: timestampDate
        } ofItemAtPath:path error:&error];
        if (error != nil) {
            NSLog(@"Failed to update modification date for %@: %@", path, error);
        }
    }

    error = nil;
    BOOL created = NO;
    if (!creationMatches) {
        created = [[NSFileManager defaultManager] setAttributes:@{
            NSFileCreationDate: timestampDate
        } ofItemAtPath:path error:&error];
        if (error != nil) {
            NSLog(@"Failed to update creation date for %@: %@", path, error);
        }
    }

    if (!updated && !created) {
        NSLog(@"Failed to synchronize any file dates for %@", path);
    }
}

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/audio_fifo.h>
#include <libavutil/opt.h>
#include <libavutil/imgutils.h>
#include <libavutil/pixdesc.h>
#include <libavutil/channel_layout.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>

}
int64_t calc_avg_bitrate(AVFormatContext *fmt, int v_stream_idx) {
    AVStream *vs = fmt->streams[v_stream_idx];

    // duration in seconds
    double duration = 0;
    if (vs->duration > 0 && vs->time_base.den > 0) {
        duration = vs->duration * av_q2d(vs->time_base);
    } else if (fmt->duration > 0) {
        duration = fmt->duration / (double)AV_TIME_BASE;
    }

    if (duration <= 0) return 0;

    int64_t file_size = avio_size(fmt->pb); // bytes
    if (file_size <= 0) return 0;

    return (int64_t)((file_size * 8) / duration);
}

static int GetVisibleFrameWidth(const AVFrame *frame, const AVCodecContext *decCtx) {
    int width = frame ? frame->width : 0;
    if (width <= 0 && decCtx != NULL) {
        width = decCtx->width;
    }
    if (frame != NULL) {
        width -= (int)frame->crop_left + (int)frame->crop_right;
    }
    return width > 0 ? width : ((decCtx != NULL) ? decCtx->width : 0);
}

static int GetVisibleFrameHeight(const AVFrame *frame, const AVCodecContext *decCtx) {
    int height = frame ? frame->height : 0;
    if (height <= 0 && decCtx != NULL) {
        height = decCtx->height;
    }
    if (frame != NULL) {
        height -= (int)frame->crop_top + (int)frame->crop_bottom;
    }
    return height > 0 ? height : ((decCtx != NULL) ? decCtx->height : 0);
}
@implementation FFmpegWrapper

- (void)printMediaInfo:(NSString *)filePath {
    AVFormatContext *fmtCtx = NULL;
    const char *cPath = [filePath UTF8String];

    // open file
    if (avformat_open_input(&fmtCtx, cPath, NULL, NULL) != 0) {
        NSLog(@"❌ Failed to open file: %@", filePath);
        return;
    }

    // load stream info
    if (avformat_find_stream_info(fmtCtx, NULL) < 0) {
        NSLog(@"❌ Failed to find stream info");
        avformat_close_input(&fmtCtx);
        return;
    }

    av_dump_format(fmtCtx, 0, cPath, 0);

    // close file
    avformat_close_input(&fmtCtx);
}

-(void)transcodeToMOVWithInput: (NSString *)inputPath andOutput: (NSString *)outputPath andBitrateFactor: (double)bitrateFactor{
    /*
     Note: 1920x1080 video from PS5 is actually 1920x1088 (1088 = 16*68)
           We should remove the extra 8p
     */
    AVFormatContext *ifmt_ctx = NULL, *ofmt_ctx = NULL;
    AVCodecContext *v_dec_ctx = NULL, *v_enc_ctx = NULL;
    AVCodecContext *a_dec_ctx = NULL, *a_enc_ctx = NULL;
    struct SwsContext *sws_ctx = NULL;
    SwrContext *swr_ctx = NULL;
    AVAudioFifo *fifo = NULL;

    int v_stream_idx = -1, a_stream_idx = -1;
    int out_v_idx = -1, out_a_idx = -1;
    int video_visible_width = 0, video_visible_height = 0;
    int64_t next_audio_pts = 0;
    int64_t next_video_pts = 0;
    BOOL shouldProcess = YES;

    // open input file
    int ret = avformat_open_input(&ifmt_ctx, [inputPath UTF8String], NULL, NULL);
    if (ret < 0) {
        NSLog(@"❌ Failed to open input file: %@ (ret=%d)", inputPath, ret);
        return;
    }
    ret = avformat_find_stream_info(ifmt_ctx, NULL);
    if (ret < 0) {
        NSLog(@"❌ Failed to find stream info for %@ (ret=%d)", inputPath, ret);
        avformat_close_input(&ifmt_ctx);
        return;
    }

    // create context
    avformat_alloc_output_context2(&ofmt_ctx, NULL, "mov", [outputPath UTF8String]);
    if (ofmt_ctx == NULL) {
        NSLog(@"❌ Failed to create output context for %@", outputPath);
        avformat_close_input(&ifmt_ctx);
        return;
    }

    for (int i = 0; i < ifmt_ctx->nb_streams; i++) {
        AVStream *in_stream = ifmt_ctx->streams[i];
        if (in_stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO && v_stream_idx < 0) {
            v_stream_idx = i;
            const AVCodec *dec = avcodec_find_decoder(in_stream->codecpar->codec_id);
            if (dec == NULL) {
                NSLog(@"❌ Failed to find video decoder for stream %d", i);
                continue;
            }
            v_dec_ctx = avcodec_alloc_context3(dec);
            if (v_dec_ctx == NULL) {
                NSLog(@"❌ Failed to allocate video decoder context");
                continue;
            }
            ret = avcodec_parameters_to_context(v_dec_ctx, in_stream->codecpar);
            if (ret < 0) {
                NSLog(@"❌ Failed to copy video codec parameters (ret=%d)", ret);
                continue;
            }
            ret = avcodec_open2(v_dec_ctx, dec, NULL);
            if (ret < 0) {
                NSLog(@"❌ Failed to open video decoder (ret=%d)", ret);
                continue;
            }

            video_visible_width = v_dec_ctx->width;
            video_visible_height = v_dec_ctx->height;
            if (in_stream->codecpar->width == 1920 && in_stream->codecpar->height == 1088) {
                video_visible_height = 1080;
            }

            const AVCodec *enc = avcodec_find_encoder_by_name("hevc_videotoolbox");
            if (enc == NULL) {
                NSLog(@"❌ Failed to find hevc_videotoolbox encoder");
                continue;
            }
            v_enc_ctx = avcodec_alloc_context3(enc);
            if (v_enc_ctx == NULL) {
                NSLog(@"❌ Failed to allocate video encoder context");
                continue;
            }
            v_enc_ctx->width = video_visible_width;
            v_enc_ctx->height = video_visible_height;
            v_enc_ctx->pix_fmt = AV_PIX_FMT_P010LE;
            int64_t av1_br = calc_avg_bitrate(ifmt_ctx, v_stream_idx);
            v_enc_ctx->bit_rate = (int64_t)(bitrateFactor * av1_br);
            if (v_enc_ctx->bit_rate <= 0) {
                v_enc_ctx->bit_rate = 17000000;
            }

            AVRational input_framerate = in_stream->avg_frame_rate.num > 0 ? in_stream->avg_frame_rate : in_stream->r_frame_rate;
            if (input_framerate.num <= 0 || input_framerate.den <= 0) {
                input_framerate = (AVRational){60000, 1001};
            }
            v_enc_ctx->framerate = input_framerate;
            v_enc_ctx->time_base = av_inv_q(v_enc_ctx->framerate);

            v_enc_ctx->color_range = AVCOL_RANGE_MPEG;
            v_enc_ctx->color_primaries = AVCOL_PRI_BT2020;
            v_enc_ctx->color_trc = AVCOL_TRC_SMPTE2084;
            v_enc_ctx->colorspace = AVCOL_SPC_BT2020_NCL;
            v_enc_ctx->gop_size = av_rescale_q(4, (AVRational){1, 1}, v_enc_ctx->framerate);
            if (v_enc_ctx->gop_size <= 0) {
                v_enc_ctx->gop_size = 240;
            }

            if (ofmt_ctx->oformat->flags & AVFMT_GLOBALHEADER) {
                v_enc_ctx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
            }

            AVDictionary *opts = NULL;
            av_dict_set(&opts, "preset", "ultra_slow", 0);
            av_dict_set(&opts, "profile", "main10", 0);
            av_dict_set(&opts, "quality", "1", 0);
            av_dict_set(&opts, "realtime", "0", 0);
            char br[32];
            snprintf(br, sizeof(br), "%lld", v_enc_ctx->bit_rate / 10 * 12);
            av_dict_set(&opts, "maxrate", br, 0);
            av_dict_set(&opts, "bufsize", br, 0);
            ret = avcodec_open2(v_enc_ctx, enc, &opts);
            av_dict_free(&opts);
            if (ret < 0) {
                NSLog(@"❌ Failed to open video encoder (ret=%d)", ret);
                continue;
            }

            NSLog(@"video input coded=%dx%d visible=%dx%d fps=%d/%d bitrate=%lld maxrate=%s gop=%d",
                  v_dec_ctx->width,
                  v_dec_ctx->height,
                  v_enc_ctx->width,
                  v_enc_ctx->height,
                  v_enc_ctx->framerate.num,
                  v_enc_ctx->framerate.den,
                  v_enc_ctx->bit_rate,
                  br,
                  v_enc_ctx->gop_size);

            AVStream *out_s = avformat_new_stream(ofmt_ctx, NULL);
            if (out_s == NULL) {
                NSLog(@"❌ Failed to create output video stream");
                continue;
            }
            ret = avcodec_parameters_from_context(out_s->codecpar, v_enc_ctx);
            if (ret < 0) {
                NSLog(@"❌ Failed to copy video encoder parameters to stream (ret=%d)", ret);
                continue;
            }
            out_s->codecpar->codec_tag = MKTAG('h','v','c','1');
            out_s->time_base = v_enc_ctx->time_base;
            out_v_idx = out_s->index;

            sws_ctx = sws_getContext(v_dec_ctx->width, v_enc_ctx->height, v_dec_ctx->pix_fmt,
                                     v_enc_ctx->width, v_enc_ctx->height, v_enc_ctx->pix_fmt,
                                     SWS_BICUBIC, NULL, NULL, NULL);
            if (sws_ctx == NULL) {
                NSLog(@"❌ Failed to create sws context for video conversion");
                continue;
            }
        }
        else if (in_stream->codecpar->codec_type == AVMEDIA_TYPE_AUDIO && a_stream_idx < 0) {
            a_stream_idx = i;
            const AVCodec *dec = avcodec_find_decoder(in_stream->codecpar->codec_id);
            if (dec == NULL) {
                NSLog(@"❌ Failed to find audio decoder for stream %d", i);
                continue;
            }
            a_dec_ctx = avcodec_alloc_context3(dec);
            if (a_dec_ctx == NULL) {
                NSLog(@"❌ Failed to allocate audio decoder context");
                continue;
            }
            ret = avcodec_parameters_to_context(a_dec_ctx, in_stream->codecpar);
            if (ret < 0) {
                NSLog(@"❌ Failed to copy audio codec parameters (ret=%d)", ret);
                continue;
            }
            ret = avcodec_open2(a_dec_ctx, dec, NULL);
            if (ret < 0) {
                NSLog(@"❌ Failed to open audio decoder (ret=%d)", ret);
                continue;
            }

            const AVCodec *enc = avcodec_find_encoder(AV_CODEC_ID_AAC);
            if (enc == NULL) {
                NSLog(@"❌ Failed to find AAC encoder");
                continue;
            }
            a_enc_ctx = avcodec_alloc_context3(enc);
            if (a_enc_ctx == NULL) {
                NSLog(@"❌ Failed to allocate audio encoder context");
                continue;
            }
            a_enc_ctx->sample_rate = a_dec_ctx->sample_rate;
            ret = av_channel_layout_copy(&a_enc_ctx->ch_layout, &a_dec_ctx->ch_layout);
            if (ret < 0) {
                NSLog(@"❌ Failed to copy audio channel layout (ret=%d)", ret);
                continue;
            }
            a_enc_ctx->sample_fmt = AV_SAMPLE_FMT_FLTP;
            a_enc_ctx->bit_rate = 192000;
            a_enc_ctx->time_base = (AVRational){1, a_enc_ctx->sample_rate};
            if (ofmt_ctx->oformat->flags & AVFMT_GLOBALHEADER) {
                a_enc_ctx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
            }
            ret = avcodec_open2(a_enc_ctx, enc, NULL);
            if (ret < 0) {
                NSLog(@"❌ Failed to open audio encoder (ret=%d)", ret);
                continue;
            }

            AVStream *out_s = avformat_new_stream(ofmt_ctx, NULL);
            if (out_s == NULL) {
                NSLog(@"❌ Failed to create output audio stream");
                continue;
            }
            ret = avcodec_parameters_from_context(out_s->codecpar, a_enc_ctx);
            if (ret < 0) {
                NSLog(@"❌ Failed to copy audio encoder parameters to stream (ret=%d)", ret);
                continue;
            }
            out_s->time_base = a_enc_ctx->time_base;
            out_a_idx = out_s->index;

            swr_ctx = swr_alloc();
            if (swr_ctx == NULL) {
                NSLog(@"❌ Failed to allocate swr context");
                continue;
            }
            ret = swr_alloc_set_opts2(&swr_ctx, &a_enc_ctx->ch_layout, AV_SAMPLE_FMT_FLTP, a_enc_ctx->sample_rate,
                                      &a_dec_ctx->ch_layout, a_dec_ctx->sample_fmt, a_dec_ctx->sample_rate, 0, NULL);
            if (ret < 0) {
                NSLog(@"❌ Failed to configure swr context (ret=%d)", ret);
                continue;
            }
            ret = swr_init(swr_ctx);
            if (ret < 0) {
                NSLog(@"❌ Failed to initialize swr context (ret=%d)", ret);
                continue;
            }

            fifo = av_audio_fifo_alloc(a_enc_ctx->sample_fmt, a_enc_ctx->ch_layout.nb_channels, 1024 * 10);
            if (fifo == NULL) {
                NSLog(@"❌ Failed to allocate audio fifo");
                continue;
            }
        }
    }

    if (v_dec_ctx == NULL || v_enc_ctx == NULL || sws_ctx == NULL || out_v_idx < 0) {
        NSLog(@"❌ Video pipeline initialization failed for %@", inputPath);
        shouldProcess = NO;
    }
    if (shouldProcess && a_stream_idx >= 0 && (a_dec_ctx == NULL || a_enc_ctx == NULL || swr_ctx == NULL || fifo == NULL || out_a_idx < 0)) {
        NSLog(@"❌ Audio pipeline initialization failed for %@", inputPath);
        shouldProcess = NO;
    }

    // open output file
    NSString *outputDir = [[outputPath stringByDeletingLastPathComponent] stringByStandardizingPath];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:outputDir]) {
        NSError *err = nil;
        [fm createDirectoryAtPath:outputDir withIntermediateDirectories:YES attributes:nil error:&err];
        if (err) {
            NSLog(@"❌ Failed to create output directory: %@", err);
            shouldProcess = NO;
        }
    }
    AVPacket *pkt = NULL;
    AVFrame *frame = NULL;
    AVFrame *sw_frame = NULL;

    if (shouldProcess && !(ofmt_ctx->oformat->flags & AVFMT_NOFILE)) {
        ret = avio_open(&ofmt_ctx->pb, [outputPath UTF8String], AVIO_FLAG_WRITE);
        if (ret < 0) {
            NSLog(@"❌ Failed to open output file %@ (ret=%d)", outputPath, ret);
            shouldProcess = NO;
        }
    }
    if (shouldProcess) {
        AVDictionary *m_opts = NULL;
        av_dict_set(&m_opts, "movflags", "faststart", 0);
        ret = avformat_write_header(ofmt_ctx, &m_opts);
        av_dict_free(&m_opts);
        if (ret < 0) {
            NSLog(@"❌ avformat_write_header error: %d", ret);
            shouldProcess = NO;
        }
    }
    if (shouldProcess) {
        pkt = av_packet_alloc();
        frame = av_frame_alloc();
        sw_frame = av_frame_alloc();
        if (pkt == NULL || frame == NULL || sw_frame == NULL) {
            NSLog(@"❌ Failed to allocate packet/frame objects for transcoding");
            shouldProcess = NO;
        }
    }

    // main loop for convert
    while (shouldProcess && av_read_frame(ifmt_ctx, pkt) >= 0) {
        if (pkt->stream_index == v_stream_idx) {
            ret = avcodec_send_packet(v_dec_ctx, pkt);
            if (ret < 0) {
                NSLog(@"❌ avcodec_send_packet(video decoder) failed: %d", ret);
            } else {
                while ((ret = avcodec_receive_frame(v_dec_ctx, frame)) == 0) {
                    int crop_left = (int)frame->crop_left;
                    int crop_top = (int)frame->crop_top;
                    int visible_width = GetVisibleFrameWidth(frame, v_dec_ctx);
                    int visible_height = GetVisibleFrameHeight(frame, v_dec_ctx);

                    if (visible_width != v_enc_ctx->width || visible_height != v_enc_ctx->height) {
                        NSLog(@"⚠️ visible frame size changed from %dx%d to %dx%d (coded=%dx%d crop l=%d r=%zu t=%d b=%zu)",
                              v_enc_ctx->width,
                              v_enc_ctx->height,
                              visible_width,
                              visible_height,
                              frame->width,
                              frame->height,
                              crop_left,
                              frame->crop_right,
                              crop_top,
                              frame->crop_bottom);
                    }


                    av_frame_unref(sw_frame);
                    sw_frame->width = v_enc_ctx->width;
                    sw_frame->height = v_enc_ctx->height;
                    sw_frame->format = v_enc_ctx->pix_fmt;
                    ret = av_frame_get_buffer(sw_frame, 0);
                    if (ret < 0) {
                        NSLog(@"❌ av_frame_get_buffer(video) failed: %d", ret);
                        continue;
                    }
                    ret = av_frame_make_writable(sw_frame);
                    if (ret < 0) {
                        NSLog(@"❌ av_frame_make_writable(video) failed: %d", ret);
                        continue;
                    }

                    int actual_height = frame->height == 1088 ? 1080 : frame->height;

                    ret = sws_scale(sws_ctx,
                                    (const uint8_t *const *)frame->data,
                                    frame->linesize,
                                    0,
                                    actual_height,
                                    sw_frame->data,
                                    sw_frame->linesize);
                    if (ret <= 0) {
                        NSLog(@"❌ sws_scale failed for video frame pts=%lld", frame->pts);
                        continue;
                    }

                    sw_frame->pts = next_video_pts++;

                    ret = avcodec_send_frame(v_enc_ctx, sw_frame);
                    if (ret < 0) {
                        NSLog(@"❌ avcodec_send_frame(video encoder) failed: %d", ret);
                    } else {
                        AVPacket *opkt = av_packet_alloc();
                        if (opkt == NULL) {
                            NSLog(@"❌ Failed to allocate output video packet");
                        } else {
                            while ((ret = avcodec_receive_packet(v_enc_ctx, opkt)) == 0) {
                                av_packet_rescale_ts(opkt, v_enc_ctx->time_base, ofmt_ctx->streams[out_v_idx]->time_base);
                                opkt->stream_index = out_v_idx;
                                ret = av_interleaved_write_frame(ofmt_ctx, opkt);
                                if (ret < 0) {
                                    NSLog(@"❌ av_interleaved_write_frame(video) failed: %d", ret);
                                }
                                av_packet_unref(opkt);
                            }
                            if (ret != AVERROR(EAGAIN) && ret != AVERROR_EOF) {
                                NSLog(@"❌ avcodec_receive_packet(video encoder) failed: %d", ret);
                            }
                            av_packet_free(&opkt);
                        }
                    }
                }
                if (ret != AVERROR(EAGAIN) && ret != AVERROR_EOF) {
                    NSLog(@"❌ avcodec_receive_frame(video decoder) failed: %d", ret);
                }
            }
        } else if (pkt->stream_index == a_stream_idx) {
            ret = avcodec_send_packet(a_dec_ctx, pkt);
            if (ret < 0) {
                NSLog(@"❌ avcodec_send_packet(audio decoder) failed: %d", ret);
            } else {
                while ((ret = avcodec_receive_frame(a_dec_ctx, frame)) == 0) {
                    uint8_t **out_data = NULL;
                    int out_linesize = 0;
                    ret = av_samples_alloc_array_and_samples(&out_data,
                                                             &out_linesize,
                                                             a_enc_ctx->ch_layout.nb_channels,
                                                             frame->nb_samples,
                                                             a_enc_ctx->sample_fmt,
                                                             0);
                    if (ret < 0) {
                        NSLog(@"❌ av_samples_alloc_array_and_samples failed: %d", ret);
                        continue;
                    }

                    ret = swr_convert(swr_ctx,
                                      out_data,
                                      frame->nb_samples,
                                      (const uint8_t **)frame->data,
                                      frame->nb_samples);
                    if (ret < 0) {
                        NSLog(@"❌ swr_convert failed: %d", ret);
                        if (out_data != NULL) {
                            av_freep(&out_data[0]);
                            av_freep(&out_data);
                        }
                        continue;
                    }

                    ret = av_audio_fifo_write(fifo, (void **)out_data, frame->nb_samples);
                    if (ret < frame->nb_samples) {
                        NSLog(@"❌ av_audio_fifo_write wrote only %d of %d samples", ret, frame->nb_samples);
                    }
                    if (out_data != NULL) {
                        av_freep(&out_data[0]);
                        av_freep(&out_data);
                    }

                    while (av_audio_fifo_size(fifo) >= a_enc_ctx->frame_size) {
                        AVFrame *f_frame = av_frame_alloc();
                        if (f_frame == NULL) {
                            NSLog(@"❌ Failed to allocate audio frame for encoder");
                            break;
                        }
                        f_frame->nb_samples = a_enc_ctx->frame_size;
                        f_frame->format = a_enc_ctx->sample_fmt;
                        av_channel_layout_copy(&f_frame->ch_layout, &a_enc_ctx->ch_layout);
                        ret = av_frame_get_buffer(f_frame, 0);
                        if (ret < 0) {
                            NSLog(@"❌ av_frame_get_buffer(audio) failed: %d", ret);
                            av_frame_free(&f_frame);
                            break;
                        }
                        ret = av_audio_fifo_read(fifo, (void **)f_frame->data, a_enc_ctx->frame_size);
                        if (ret < a_enc_ctx->frame_size) {
                            NSLog(@"❌ av_audio_fifo_read read only %d of %d samples", ret, a_enc_ctx->frame_size);
                            av_frame_free(&f_frame);
                            break;
                        }
                        f_frame->pts = next_audio_pts;
                        next_audio_pts += f_frame->nb_samples;

                        ret = avcodec_send_frame(a_enc_ctx, f_frame);
                        if (ret < 0) {
                            NSLog(@"❌ avcodec_send_frame(audio encoder) failed: %d", ret);
                        } else {
                            AVPacket *opkt = av_packet_alloc();
                            if (opkt == NULL) {
                                NSLog(@"❌ Failed to allocate output audio packet");
                            } else {
                                while ((ret = avcodec_receive_packet(a_enc_ctx, opkt)) == 0) {
                                    av_packet_rescale_ts(opkt, a_enc_ctx->time_base, ofmt_ctx->streams[out_a_idx]->time_base);
                                    opkt->stream_index = out_a_idx;
                                    ret = av_interleaved_write_frame(ofmt_ctx, opkt);
                                    if (ret < 0) {
                                        NSLog(@"❌ av_interleaved_write_frame(audio) failed: %d", ret);
                                    }
                                    av_packet_unref(opkt);
                                }
                                if (ret != AVERROR(EAGAIN) && ret != AVERROR_EOF) {
                                    NSLog(@"❌ avcodec_receive_packet(audio encoder) failed: %d", ret);
                                }
                                av_packet_free(&opkt);
                            }
                        }
                        av_frame_free(&f_frame);
                    }
                }
                if (ret != AVERROR(EAGAIN) && ret != AVERROR_EOF) {
                    NSLog(@"❌ avcodec_receive_frame(audio decoder) failed: %d", ret);
                }
            }
        }
        av_packet_unref(pkt);
    }

    // process remained audio
    if (shouldProcess && fifo && a_enc_ctx && out_a_idx >= 0 && av_audio_fifo_size(fifo) > 0) {
        AVFrame *f_frame = av_frame_alloc();
        if (f_frame != NULL) {
            f_frame->nb_samples = av_audio_fifo_size(fifo);
            f_frame->format = a_enc_ctx->sample_fmt;
            av_channel_layout_copy(&f_frame->ch_layout, &a_enc_ctx->ch_layout);
            ret = av_frame_get_buffer(f_frame, 0);
            if (ret < 0) {
                NSLog(@"❌ av_frame_get_buffer(audio flush) failed: %d", ret);
            } else {
                ret = av_audio_fifo_read(fifo, (void **)f_frame->data, f_frame->nb_samples);
                if (ret < f_frame->nb_samples) {
                    NSLog(@"❌ av_audio_fifo_read(audio flush) read only %d of %d samples", ret, f_frame->nb_samples);
                } else {
                    f_frame->pts = next_audio_pts;
                    ret = avcodec_send_frame(a_enc_ctx, f_frame);
                    if (ret < 0) {
                        NSLog(@"❌ avcodec_send_frame(audio flush) failed: %d", ret);
                    } else {
                        AVPacket *opkt = av_packet_alloc();
                        if (opkt != NULL) {
                            while ((ret = avcodec_receive_packet(a_enc_ctx, opkt)) == 0) {
                                av_packet_rescale_ts(opkt, a_enc_ctx->time_base, ofmt_ctx->streams[out_a_idx]->time_base);
                                opkt->stream_index = out_a_idx;
                                ret = av_interleaved_write_frame(ofmt_ctx, opkt);
                                if (ret < 0) {
                                    NSLog(@"❌ av_interleaved_write_frame(audio flush) failed: %d", ret);
                                }
                                av_packet_unref(opkt);
                            }
                            if (ret != AVERROR(EAGAIN) && ret != AVERROR_EOF) {
                                NSLog(@"❌ avcodec_receive_packet(audio flush) failed: %d", ret);
                            }
                            av_packet_free(&opkt);
                        }
                    }
                }
            }
            av_frame_free(&f_frame);
        }
    }

    // process remained video
    if (shouldProcess && v_enc_ctx != NULL && ofmt_ctx != NULL && out_v_idx >= 0) {
        ret = avcodec_send_frame(v_enc_ctx, NULL);
        if (ret < 0) {
            NSLog(@"❌ avcodec_send_frame(video flush) failed: %d", ret);
        }
        AVPacket *flush_pkt = av_packet_alloc();
        if (flush_pkt != NULL) {
            while ((ret = avcodec_receive_packet(v_enc_ctx, flush_pkt)) == 0) {
                av_packet_rescale_ts(flush_pkt, v_enc_ctx->time_base, ofmt_ctx->streams[out_v_idx]->time_base);
                flush_pkt->stream_index = out_v_idx;
                ret = av_interleaved_write_frame(ofmt_ctx, flush_pkt);
                if (ret < 0) {
                    NSLog(@"❌ av_interleaved_write_frame(video flush) failed: %d", ret);
                }
                av_packet_unref(flush_pkt);
            }
            if (ret != AVERROR(EAGAIN) && ret != AVERROR_EOF) {
                NSLog(@"❌ avcodec_receive_packet(video flush) failed: %d", ret);
            }
            av_packet_free(&flush_pkt);
        }
    }

    if (shouldProcess && ofmt_ctx != NULL) {
        ret = av_write_trailer(ofmt_ctx);
        if (ret < 0) {
            NSLog(@"❌ av_write_trailer failed: %d", ret);
        }
    }
    // clean
    if (sws_ctx) sws_freeContext(sws_ctx);
    if (swr_ctx) swr_free(&swr_ctx);
    if (fifo) av_audio_fifo_free(fifo);
    avcodec_free_context(&v_dec_ctx);
    avcodec_free_context(&v_enc_ctx);
    avcodec_free_context(&a_dec_ctx);
    avcodec_free_context(&a_enc_ctx);
    av_frame_free(&frame);
    av_frame_free(&sw_frame);
    av_packet_free(&pkt);
    avformat_close_input(&ifmt_ctx);
    if (ofmt_ctx) {
        if (!(ofmt_ctx->oformat->flags & AVFMT_NOFILE)) avio_closep(&ofmt_ctx->pb);
        avformat_free_context(ofmt_ctx);
    }

    NSLog(@"Convert Finished: %@", outputPath);
    SynchronizeFileDatesForPath(outputPath);
}
@end
