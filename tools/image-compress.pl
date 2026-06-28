#!/usr/bin/env perl
# image-compress.pl — MCP server for image_compress tool
# Compresses/resizes images to a target size (default: 1MB)
# Usage: standalone MCP server (started by opencode as external MCP)
#
# Depends: ImageMagick (convert/magick)

use strict;
use warnings;
use utf8;
use JSON::PP;
use File::Basename;

binmode(STDIN,  ":utf8");
binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

my $json = JSON::PP->new->allow_nonref;

sub respond {
    my ($id, $result) = @_;
    my $response = { jsonrpc => "2.0", id => $id, result => $result };
    print $json->encode($response) . "\n";
    STDOUT->flush();
}

sub respond_error {
    my ($id, $code, $message) = @_;
    my $response = { jsonrpc => "2.0", id => $id, error => { code => $code, message => $message } };
    print $json->encode($response) . "\n";
    STDOUT->flush();
}

sub _resolve_file {
    my ($url) = @_;

    # Yandex Disk
    if ($url =~ m{disk\.yandex\.(?:ru|com|by|kz|ee)}i || $url =~ m{yadi\.sk}i) {
        require URI::Escape;
        my $pub_key = URI::Escape::uri_escape($url);
        my $api = "https://cloud-api.yandex.net/v1/disk/public/resources/download?public_key=$pub_key";
        my $atmp = "/tmp/ic_yadisk_api_$$.json";
        system('curl', '-sS', '--max-time', '15', '-o', $atmp, $api);
        die "Yandex Disk API failed" unless -e $atmp && -s $atmp;
        open(my $afh, '<:utf8', $atmp) or die "Cannot read $atmp ($!)";
        local $/; my $abody = <$afh>; close $afh; unlink $atmp;
        my $adata = eval { $json->decode($abody) };
        die "Yandex Disk API: bad response" unless $adata && $adata->{href};
        $url = $adata->{href};
    }

    my $tmp = "/tmp/ic_download_$$.jpg";
    my $exit = system('curl', '-sS', '-L', '--max-time', '120', '-o', $tmp, $url);
    die "Download failed (exit=$exit)" unless -e $tmp && -s $tmp;
    return $tmp;
}

sub do_compress {
    my ($args) = @_;
    my $source    = $args->{source}    // '';
    my $max_size  = $args->{max_size}  // 1;  # MB
    my $output    = $args->{output}    // '';  # optional output path

    die "Missing required: source (url or file_path)" unless $source;

    my $tmp;
    if ($source =~ m{^https?://}i) {
        $tmp = _resolve_file($source);
    } else {
        $tmp = $source;
        die "Source file not found: $source" unless -e $source;
    }

    my $max_bytes = $max_size * 1024 * 1024;
    my $out = $output || "/tmp/ic_compressed_$$.jpg";

    # Start with quality 85, reduce until under max_size
    my $quality = 85;
    my $resize  = '';
    my $attempts = 0;
    while ($attempts < 10) {
        $attempts++;
        my @cmd = ('magick', $tmp);
        push @cmd, '-resize', $resize if $resize;
        push @cmd, '-quality', $quality, $out;
        system(@cmd);
        die "ImageMagick failed" unless -e $out;

        my $size = -s $out;
        last if $size <= $max_bytes;

        if ($quality > 20) {
            $quality -= 10;
        } else {
            # Reduce resolution
            my ($w, $h) = (0, 0);
            open(my $fh, '-|', 'magick', $tmp, '-format', '%w %h', 'info:') or next;
            my $dims = <$fh>; close $fh;
            if ($dims =~ /(\d+)\s+(\d+)/) {
                $w = $1; $h = $2;
                $resize = int($w * 0.8) . 'x' . int($h * 0.8);
                $quality = 85;
            }
        }
    }

    unlink $tmp unless $source eq $tmp;

    my $final_size = -s $out;
    return {
        compressed_path => $out,
        size_bytes      => $final_size,
        size_mb         => sprintf("%.2f", $final_size / 1024 / 1024),
        under_limit     => $final_size <= $max_bytes ? JSON::PP::true : JSON::PP::false,
    };
}

# MCP Main Loop
while (my $line = <STDIN>) {
    chomp $line;
    next unless $line && $line =~ /\S/;

    my $msg = eval { $json->decode($line) };
    if ($@ || !$msg) {
        print STDERR "Invalid JSON-RPC: $@\n";
        next;
    }

    my $id     = $msg->{id};
    my $method = $msg->{method} // '';
    my $params = $msg->{params} // {};

    next unless defined $id;

    if ($method eq 'initialize') {
        respond($id, {
            protocolVersion => '2024-11-05',
            capabilities    => { tools => {} },
            serverInfo      => {
                name    => 'image-compress',
                version => '1.0.0',
            },
        });
    }
    elsif ($method eq 'ping') {
        respond($id, {});
    }
    elsif ($method eq 'tools/list') {
        respond($id, {
            tools => [
                {
                    name        => 'image_compress',
                    description => 'Compress an image to a target size (default: 1MB). Accepts URL (including Yandex Disk) or local file path. Uses ImageMagick to reduce quality and/or resolution.',
                    inputSchema => {
                        type       => 'object',
                        properties => {
                            source => {
                                type        => 'string',
                                description => 'URL or local file path of the image to compress',
                            },
                            max_size => {
                                type        => 'number',
                                description => 'Target max size in MB (default: 1)',
                            },
                            output => {
                                type        => 'string',
                                description => 'Optional output file path (default: /tmp/ic_compressed_*.jpg)',
                            },
                        },
                        required => ['source'],
                    },
                },
            ],
        });
    }
    elsif ($method eq 'tools/call') {
        my $tool_name = $params->{name} // '';
        my $tool_args = $params->{arguments} // {};

        if ($tool_name eq 'image_compress') {
            eval {
                my $result = do_compress($tool_args);
                respond($id, {
                    content => [
                        { type => 'text', text => $json->encode($result) },
                    ],
                });
            };
            if ($@) {
                my $err = $@;
                chomp $err;
                respond_error($id, -32603, "image_compress error: $err");
            }
        }
        else {
            respond_error($id, -32601, "Unknown tool: $tool_name");
        }
    }
    else {
        respond_error($id, -32601, "Method not found: $method");
    }
}
