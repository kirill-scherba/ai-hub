#!/usr/bin/env perl
# vision-mcp.pl — MCP server for vision_analyze tool
# Analyzes images using OpenAI Vision API (GPT-4o-mini)
# Usage: standalone MCP server (started by opencode as external MCP)
#
# Env: OPENAI_API_KEY (required), VISION_MODEL (optional, default: gpt-4o-mini)

use strict;
use warnings;
use utf8;
use JSON::PP;
use MIME::Base64;

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

sub _compress_image {
    my ($file_path) = @_;
    # Resize to max 2048px on longest side, convert to JPEG quality 75
    my $tmp = "/tmp/vision_compress_$$.jpg";
    system('magick', $file_path, '-resize', '2048x2048>', '-quality', '75', $tmp);
    die "Image compression failed" unless -e $tmp;
    return $tmp;
}

sub do_vision_analyze {
    my ($args) = @_;
    my $url       = $args->{url}       // '';
    my $file_path = $args->{file_path}  // '';
    my $question  = $args->{question}  // 'Describe this image in detail in Russian. What do you see?';
    my $model     = $ENV{VISION_MODEL} // 'gpt-4o-mini';
    my $compress  = defined $args->{compress} ? $args->{compress} : 1;

    my $api_key = $ENV{OPENAI_API_KEY} or die "OPENAI_API_KEY not set";

    # Resolve image source: file_path takes priority over url
    my $image_url;
    if ($file_path) {
        # Optionally compress local file
        my $source = $compress ? _compress_image($file_path) : $file_path;
        open(my $fh, '<:raw', $source) or die "Cannot read file: $source ($!)";
        local $/;
        my $data = <$fh>;
        close $fh;
        unlink $source if $compress;  # remove temp file
        my $b64 = encode_base64($data, '');
        my $mime = $compress ? 'image/jpeg' : do {
            my $ext = $file_path =~ /\.(\w+)$/ ? lc($1) : 'png';
            my %mime = (png => 'image/png', jpg => 'image/jpeg', jpeg => 'image/jpeg',
                        webp => 'image/webp', gif => 'image/gif', bmp => 'image/bmp',
                        tiff => 'image/tiff', tif => 'image/tiff');
            $mime{$ext} // 'image/png';
        };
        $image_url = "data:$mime;base64,$b64";
    } elsif ($url) {
        # Download URL locally so we can optionally compress
        my $tmp_url = "/tmp/vision_url_$$.jpg";
        my $curl_exit = system('curl', '-sS', '-L', '--max-time', '60', '-o', $tmp_url, $url);
        die "URL download failed (exit=$curl_exit): $url" unless -e $tmp_url && -s $tmp_url;
        if ($compress) {
            my $compressed = _compress_image($tmp_url);
            unlink $tmp_url;
            $tmp_url = $compressed;
        }
        open(my $fh, '<:raw', $tmp_url) or die "Cannot read downloaded file ($!)";
        local $/;
        my $data = <$fh>;
        close $fh;
        unlink $tmp_url;
        my $b64 = encode_base64($data, '');
        $image_url = "data:image/jpeg;base64,$b64";
    } else {
        die "Missing required: provide either 'url' or 'file_path'";
    }

    my $payload = {
        model => $model,
        messages => [
            {
                role => 'user',
                content => [
                    { type => 'text', text => $question },
                    { type => 'image_url', image_url => { url => $image_url } },
                ],
            },
        ],
        max_tokens => 1000,
    };

    my $body = $json->encode($payload);

    # Write body to temp file to avoid "Argument list too long"
    my $tmpfile = "/tmp/vision_mcp_req_$$.json";
    open(my $tmpfh, '>:utf8', $tmpfile) or die "Cannot write $tmpfile: $!";
    print $tmpfh $body;
    close $tmpfh;

    # HTTP POST via curl
    my ($content, $status);
    if (open(my $fh, '-|', 'curl', '-sS', '--max-time', '120',
             '-X', 'POST',
             '-H', 'Content-Type: application/json',
             '-H', "Authorization: Bearer $api_key",
             '-d', '@' . $tmpfile,
             '-o', '-', '-w', "\n%{http_code}\n",
             'https://api.openai.com/v1/chat/completions')) {
        local $/;
        my $all = <$fh>;
        close $fh;
        unlink $tmpfile;
        utf8::decode($all);
        my @parts = split /\n/, $all;
        $status  = pop @parts;
        $content = join("\n", @parts);
    } else {
        unlink $tmpfile;
        die "Failed to execute curl";
    }

    die "API error (HTTP $status): " . substr($content // '', 0, 500) unless $status eq '200';

    my $data = $json->decode($content);
    my $text  = $data->{choices}[0]{message}{content} // 'No response';
    my $tokens = $data->{usage}{total_tokens} // 0;

    return {
        description => $text,
        model       => $model,
        tokens_used => $tokens,
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
                name    => 'vision-mcp',
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
                    name        => 'vision_analyze',
                    description => 'Analyze an image using OpenAI Vision API. Provide image URL and optional question. Returns detailed description of the image content.',
                    inputSchema => {
                        type       => 'object',
                        properties => {
                            url => {
                                type        => 'string',
                                description => 'URL of the image to analyze',
                            },
                            file_path => {
                                type        => 'string',
                                description => 'Local path to an image file to analyze',
                            },
                            question => {
                                type        => 'string',
                                description => 'Optional question about the image (default: Describe in Russian)',
                            },
                            compress => {
                                type        => 'boolean',
                                description => 'Compress image before sending (default: true). Set false for full detail preservation.',
                            },
                        },
                    },
                },
            ],
        });
    }
    elsif ($method eq 'tools/call') {
        my $tool_name = $params->{name} // '';
        my $tool_args = $params->{arguments} // {};

        if ($tool_name eq 'vision_analyze') {
            eval {
                my $result = do_vision_analyze($tool_args);
                respond($id, {
                    content => [
                        { type => 'text', text => $json->encode($result) },
                    ],
                });
            };
            if ($@) {
                my $err = $@;
                chomp $err;
                respond_error($id, -32603, "vision_analyze error: $err");
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
