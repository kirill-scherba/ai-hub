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

sub _http_post_json {
    my ($url, $payload, $auth_header) = @_;
    my $body = $json->encode($payload);
    my $tmpfile = "/tmp/vision_req_$$.json";
    open(my $fh, '>:utf8', $tmpfile) or die "Cannot write $tmpfile: $!";
    print $fh $body;
    close $fh;

    my @curl = ('curl', '-sS', '--max-time', '120', '-X', 'POST',
                '-H', 'Content-Type: application/json', '-d', '@' . $tmpfile);
    push @curl, '-H', $auth_header if $auth_header;
    push @curl, '-o', '-', '-w', "\n%{http_code}\n", $url;

    open(my $fh, '-|', @curl) or die "Failed to execute curl";
    local $/;
    my $all = <$fh>;
    close $fh;
    unlink $tmpfile;
    utf8::decode($all) if $all;
    my @parts = split /\n/, $all;
    my $status = pop @parts;
    return ($status, join("\n", @parts));
}

sub _resolve_image {
    my ($args) = @_;
    my $url       = $args->{url}       // '';
    my $file_path = $args->{file_path}  // '';
    my $compress  = defined $args->{compress} ? $args->{compress} : 1;

    if ($file_path) {
        my $source = $compress ? _compress_image($file_path) : $file_path;
        open(my $fh, '<:raw', $source) or die "Cannot read file: $source ($!)";
        local $/;
        my $data = <$fh>;
        close $fh;
        unlink $source if $compress;
        my $b64 = encode_base64($data, '');
        my $mime = $compress ? 'image/jpeg' : do {
            my $ext = $file_path =~ /\.(\w+)$/ ? lc($1) : 'png';
            my %mime = (png => 'image/png', jpg => 'image/jpeg', jpeg => 'image/jpeg',
                        webp => 'image/webp', gif => 'image/gif', bmp => 'image/bmp',
                        tiff => 'image/tiff', tif => 'image/tiff');
            $mime{$ext} // 'image/png';
        };
        return { base64 => $b64, mime => $mime };
    }
    elsif ($url) {
        my $tmp = "/tmp/vision_url_$$.jpg";
        my $exit = system('curl', '-sS', '-L', '--max-time', '60', '-o', $tmp, $url);
        die "URL download failed (exit=$exit): $url" unless -e $tmp && -s $tmp;
        if ($compress) {
            my $compressed = _compress_image($tmp);
            unlink $tmp;
            $tmp = $compressed;
        }
        open(my $fh, '<:raw', $tmp) or die "Cannot read downloaded file ($!)";
        local $/;
        my $data = <$fh>;
        close $fh;
        unlink $tmp;
        return { base64 => encode_base64($data, ''), mime => 'image/jpeg' };
    }
    die "Missing required: provide either 'url' or 'file_path'";
}

sub _call_openai {
    my ($img, $question, $model) = @_;
    my $api_key = $ENV{OPENAI_API_KEY} or die "OPENAI_API_KEY not set for OpenAI model";
    my $img_url = "data:$img->{mime};base64,$img->{base64}";

    my $payload = {
        model => $model,
        messages => [{
            role => 'user',
            content => [
                { type => 'text', text => $question },
                { type => 'image_url', image_url => { url => $img_url } },
            ],
        }],
        max_tokens => 1000,
    };

    my ($status, $content) = _http_post_json(
        'https://api.openai.com/v1/chat/completions',
        $payload,
        "Authorization: Bearer $api_key",
    );
    die "OpenAI API error (HTTP $status)" unless $status eq '200';

    my $data = $json->decode($content);
    return {
        description => $data->{choices}[0]{message}{content} // 'No response',
        model       => $model,
        tokens_used => $data->{usage}{total_tokens} // 0,
    };
}

sub _call_ollama {
    my ($img, $question, $model) = @_;

    my $payload = {
        model => $model,
        messages => [{
            role    => 'user',
            content => $question,
            images  => [$img->{base64}],
        }],
        stream => JSON::PP::false,
    };

    my ($status, $content) = _http_post_json(
        'http://localhost:11434/api/chat',
        $payload,
        undef,  # no auth header
    );
    die "Ollama API error (HTTP $status)" unless $status eq '200';

    # Parse NDJSON response
    my $full_text = '';
    my $tokens;
    for my $line (split /\n/, $content) {
        next unless $line =~ /\S/;
        my $chunk = eval { $json->decode($line) };
        next unless $chunk;
        $full_text .= $chunk->{message}{content} // '';
        $tokens = $chunk->{eval_count} if $chunk->{done};
    }

    return {
        description => $full_text,
        model       => $model,
        tokens_used => $tokens // 0,
    };
}

sub do_vision_analyze {
    my ($args) = @_;
    my $question  = $args->{question}  // 'Describe this image in detail in Russian. What do you see?';
    my $model     = $args->{model} // $ENV{VISION_MODEL} // 'gpt-4o-mini';
    $args->{compress} = defined $args->{compress} ? $args->{compress} : 1;

    my $img = _resolve_image($args);

    if ($model =~ /^gpt/i) {
        return _call_openai($img, $question, $model);
    } else {
        return _call_ollama($img, $question, $model);
    }
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
                    description => 'Analyze an image using OpenAI Vision API or a local Ollama model. Provide image URL and optional question. Returns detailed description of the image content.',
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
                            model => {
                                type        => 'string',
                                description => 'Model to use: gpt-4o-mini (OpenAI, default), kimi-k2.7-code:cloud, minimax-m3:cloud, gemma4:cloud, gemma4:latest, llama3.2-vision, etc.',
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
