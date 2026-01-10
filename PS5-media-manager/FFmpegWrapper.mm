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

- (void)transcodeToMOVWithInput:(NSString *)inputPath andOutput:(NSString *) outputPath {
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
    int64_t next_audio_pts = 0;

    // open input file
    if (avformat_open_input(&ifmt_ctx, [inputPath UTF8String], NULL, NULL) < 0) return;
    if (avformat_find_stream_info(ifmt_ctx, NULL) < 0) return;

    // create context
    avformat_alloc_output_context2(&ofmt_ctx, NULL, "mov", [outputPath UTF8String]);

    for (int i = 0; i < ifmt_ctx->nb_streams; i++) {
        AVStream *in_stream = ifmt_ctx->streams[i];
        if (in_stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO && v_stream_idx < 0) {
            v_stream_idx = i;
            const AVCodec *dec = avcodec_find_decoder(in_stream->codecpar->codec_id);
            v_dec_ctx = avcodec_alloc_context3(dec);
            avcodec_parameters_to_context(v_dec_ctx, in_stream->codecpar);
            avcodec_open2(v_dec_ctx, dec, NULL);

            const AVCodec *enc = avcodec_find_encoder_by_name("hevc_videotoolbox");
            v_enc_ctx = avcodec_alloc_context3(enc);
            v_enc_ctx->width = v_dec_ctx->width;
            
            // fix height=1088
            v_enc_ctx->height = v_dec_ctx->height == 1088? 1080: v_dec_ctx->height;
            v_enc_ctx->pix_fmt = AV_PIX_FMT_P010LE;
            int64_t av1_br = calc_avg_bitrate(ifmt_ctx, v_stream_idx);
            // take 2.8x bitrate for hevc_videotoolbox
            v_enc_ctx->bit_rate = av1_br * 28 / 10;
            
            // fix framerate
            // i'm confused why the framerate can't be fixed to 59.94
            v_enc_ctx->framerate = (AVRational){60000, 1001};
            v_enc_ctx->time_base = av_inv_q(v_enc_ctx->framerate);
            
            // HDR10
            v_enc_ctx->color_range = AVCOL_RANGE_MPEG;
            v_enc_ctx->color_primaries = AVCOL_PRI_BT2020;
            v_enc_ctx->color_trc = AVCOL_TRC_SMPTE2084;
            v_enc_ctx->colorspace = AVCOL_SPC_BT2020_NCL;

            AVDictionary *opts = NULL;
            av_dict_set(&opts, "preset", "ultra_slow", 0);
            av_dict_set(&opts, "profile", "main10", 0);
            av_dict_set(&opts, "quality", "1", 0);
            av_dict_set(&opts, "realtime", "0", 0);
            char br[32];
            snprintf(br, sizeof(br), "%lld", v_enc_ctx->bit_rate / 10 * 12);
            av_dict_set(&opts, "maxrate", br, 0);
            av_dict_set(&opts, "bufsize", br, 0);
            int fps = v_enc_ctx->framerate.num / v_enc_ctx->framerate.den;
            int gop = fps * 4;
            av_dict_set_int(&opts, "gop_size", gop, 0);
            avcodec_open2(v_enc_ctx, enc, &opts);
            NSLog(@"bitrate: %lld, maxrate: %s, gop: %d", v_enc_ctx->bit_rate, br, gop);
            AVStream *out_s = avformat_new_stream(ofmt_ctx, NULL);
            avcodec_parameters_from_context(out_s->codecpar, v_enc_ctx);
            out_s->codecpar->codec_tag = MKTAG('h','v','c','1');
            out_s->time_base = v_enc_ctx->time_base;
            out_v_idx = out_s->index;
//                                                     ⬇️ enc instead of dec, to fix height=1088
            sws_ctx = sws_getContext(v_dec_ctx->width, v_enc_ctx->height, v_dec_ctx->pix_fmt,
                                     v_enc_ctx->width, v_enc_ctx->height, v_enc_ctx->pix_fmt,
                                     SWS_BICUBIC, NULL, NULL, NULL);
        }
        else if (in_stream->codecpar->codec_type == AVMEDIA_TYPE_AUDIO && a_stream_idx < 0) {
            a_stream_idx = i;
            const AVCodec *dec = avcodec_find_decoder(in_stream->codecpar->codec_id);
            a_dec_ctx = avcodec_alloc_context3(dec);
            avcodec_parameters_to_context(a_dec_ctx, in_stream->codecpar);
            avcodec_open2(a_dec_ctx, dec, NULL);

            const AVCodec *enc = avcodec_find_encoder(AV_CODEC_ID_AAC);
            a_enc_ctx = avcodec_alloc_context3(enc);
            a_enc_ctx->sample_rate = a_dec_ctx->sample_rate;
            av_channel_layout_copy(&a_enc_ctx->ch_layout, &a_dec_ctx->ch_layout);
            a_enc_ctx->sample_fmt = AV_SAMPLE_FMT_FLTP;
            a_enc_ctx->bit_rate = 192000;
            a_enc_ctx->time_base = (AVRational){1, a_enc_ctx->sample_rate};
            avcodec_open2(a_enc_ctx, enc, NULL);

            AVStream *out_s = avformat_new_stream(ofmt_ctx, NULL);
            avcodec_parameters_from_context(out_s->codecpar, a_enc_ctx);
            out_a_idx = out_s->index;

            swr_ctx = swr_alloc();
            swr_alloc_set_opts2(&swr_ctx, &a_enc_ctx->ch_layout, AV_SAMPLE_FMT_FLTP, a_enc_ctx->sample_rate,
                                &a_dec_ctx->ch_layout, a_dec_ctx->sample_fmt, a_dec_ctx->sample_rate, 0, NULL);
            swr_init(swr_ctx);

            fifo = av_audio_fifo_alloc(a_enc_ctx->sample_fmt, a_enc_ctx->ch_layout.nb_channels, 1024 * 10);
        }
    }

    // open output file
    NSString *outputDir = [[outputPath stringByDeletingLastPathComponent] stringByStandardizingPath];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:outputDir]) {
        NSError *err = nil;
        [fm createDirectoryAtPath:outputDir withIntermediateDirectories:YES attributes:nil error:&err];
        if (err) {
            NSLog(@"❌ Failed to create output directory: %@", err);
            return;
        }
    }
    if (!(ofmt_ctx->oformat->flags & AVFMT_NOFILE)) {
        avio_open(&ofmt_ctx->pb, [outputPath UTF8String], AVIO_FLAG_WRITE);
    }
    AVDictionary *m_opts = NULL;
    av_dict_set(&m_opts, "movflags", "faststart", 0);
    int retval = avformat_write_header(ofmt_ctx, &m_opts);
    if (retval < 0) {
        NSLog(@"avformat_write_header error: %d", retval);
    }
    AVPacket *pkt = av_packet_alloc();
    AVFrame *frame = av_frame_alloc();
    AVFrame *sw_frame = av_frame_alloc();

    // main loop for convert
    while (av_read_frame(ifmt_ctx, pkt) >= 0) {
        if (pkt->stream_index == v_stream_idx) {
            if (avcodec_send_packet(v_dec_ctx, pkt) == 0) {
                while (avcodec_receive_frame(v_dec_ctx, frame) == 0) {
                    av_frame_make_writable(sw_frame);
                    sw_frame->width = v_enc_ctx->width;
                    sw_frame->height = v_enc_ctx->height;
                    sw_frame->format = v_enc_ctx->pix_fmt;
                    av_frame_get_buffer(sw_frame, 0);
                    
                    // fix height=1088
                    int actual_height = frame->height == 1088? 1080: frame->height;
                    
                    sws_scale(sws_ctx, (const uint8_t *const *)frame->data, frame->linesize, 0, actual_height, sw_frame->data, sw_frame->linesize);
                    sw_frame->pts = av_rescale_q(frame->pts, ifmt_ctx->streams[v_stream_idx]->time_base, v_enc_ctx->time_base);
                    
                    if (avcodec_send_frame(v_enc_ctx, sw_frame) == 0) {
                        AVPacket *opkt = av_packet_alloc();
                        while (avcodec_receive_packet(v_enc_ctx, opkt) == 0) {
                            av_packet_rescale_ts(opkt, v_enc_ctx->time_base, ofmt_ctx->streams[out_v_idx]->time_base);
                            opkt->stream_index = out_v_idx;
                            av_interleaved_write_frame(ofmt_ctx, opkt);
                            av_packet_unref(opkt);
                        }
                        av_packet_free(&opkt);
                    }
                    av_frame_unref(sw_frame);
                }
            }
        } else if (pkt->stream_index == a_stream_idx) {
            if (avcodec_send_packet(a_dec_ctx, pkt) == 0) {
                while (avcodec_receive_frame(a_dec_ctx, frame) == 0) {
                    uint8_t **out_data = NULL;
                    int out_linesize;
                    av_samples_alloc_array_and_samples(&out_data, &out_linesize, a_enc_ctx->ch_layout.nb_channels, frame->nb_samples, a_enc_ctx->sample_fmt, 0);
                    swr_convert(swr_ctx, out_data, frame->nb_samples, (const uint8_t **)frame->data, frame->nb_samples);
                    av_audio_fifo_write(fifo, (void **)out_data, frame->nb_samples);
                    av_freep(&out_data[0]);
                    free(out_data);

                    while (av_audio_fifo_size(fifo) >= a_enc_ctx->frame_size) {
                        AVFrame *f_frame = av_frame_alloc();
                        f_frame->nb_samples = a_enc_ctx->frame_size;
                        f_frame->format = a_enc_ctx->sample_fmt;
                        av_channel_layout_copy(&f_frame->ch_layout, &a_enc_ctx->ch_layout);
                        av_frame_get_buffer(f_frame, 0);
                        av_audio_fifo_read(fifo, (void **)f_frame->data, a_enc_ctx->frame_size);
                        f_frame->pts = next_audio_pts;
                        next_audio_pts += f_frame->nb_samples;

                        if (avcodec_send_frame(a_enc_ctx, f_frame) == 0) {
                            AVPacket *opkt = av_packet_alloc();
                            while (avcodec_receive_packet(a_enc_ctx, opkt) == 0) {
                                av_packet_rescale_ts(opkt, a_enc_ctx->time_base, ofmt_ctx->streams[out_a_idx]->time_base);
                                opkt->stream_index = out_a_idx;
                                av_interleaved_write_frame(ofmt_ctx, opkt);
                                av_packet_unref(opkt);
                            }
                            av_packet_free(&opkt);
                        }
                        av_frame_free(&f_frame);
                    }
                }
            }
        }
        av_packet_unref(pkt);
    }

    // process remained audio
    if (fifo && av_audio_fifo_size(fifo) > 0) {
        AVFrame *f_frame = av_frame_alloc();
        f_frame->nb_samples = av_audio_fifo_size(fifo);
        f_frame->format = a_enc_ctx->sample_fmt;
        av_channel_layout_copy(&f_frame->ch_layout, &a_enc_ctx->ch_layout);
        av_frame_get_buffer(f_frame, 0);
        av_audio_fifo_read(fifo, (void **)f_frame->data, f_frame->nb_samples);
        f_frame->pts = next_audio_pts;
        avcodec_send_frame(a_enc_ctx, f_frame);
        AVPacket *opkt = av_packet_alloc();
        while (avcodec_receive_packet(a_enc_ctx, opkt) == 0) {
            av_packet_rescale_ts(opkt, a_enc_ctx->time_base, ofmt_ctx->streams[out_a_idx]->time_base);
            opkt->stream_index = out_a_idx;
            av_interleaved_write_frame(ofmt_ctx, opkt);
            av_packet_unref(opkt);
        }
        av_packet_free(&opkt);
        av_frame_free(&f_frame);
    }

    // process remained video
    avcodec_send_frame(v_enc_ctx, NULL);
    AVPacket *flush_pkt = av_packet_alloc();
    while (avcodec_receive_packet(v_enc_ctx, flush_pkt) == 0) {
        av_packet_rescale_ts(flush_pkt, v_enc_ctx->time_base, ofmt_ctx->streams[out_v_idx]->time_base);
        flush_pkt->stream_index = out_v_idx;
        av_interleaved_write_frame(ofmt_ctx, flush_pkt);
        av_packet_unref(flush_pkt);
    }
    av_packet_free(&flush_pkt);

    av_write_trailer(ofmt_ctx);

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

    NSLog(@"Convert Finished");
}
@end
