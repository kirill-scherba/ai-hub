#!/usr/bin/env perl
# vision-mcp.pl — MCP server for the image tools: vision_analyze and image_gen
# Analyzes images using OpenAI Vision API (GPT-4o-mini) or a local Ollama,
# and generates images from a text prompt using the OpenAI Images API.
# Usage: standalone MCP server (started by opencode or the gateway as an external MCP)
#
# Env: OPENAI_API_KEY (required for OpenAI models), VISION_MODEL (optional, default: gpt-4o-mini)
#      IMAGE_DIR (optional, default: <home>/Pictures/anytext), IMAGE_BASE_URL (optional: public URL
#      of that folder), IMAGE_MODEL (optional, default: gpt-image-2), IMAGE_SIZE (optional, 1024x1024)
#
# Both tools need a model key, which is exactly why they live in their own server and not in the
# tool generator: a key belongs to the server that uses it, not to a sandbox that runs arbitrary code.

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
    my ($url, $payload, $auth_header, $timeout) = @_;
    $timeout //= 120;
    my $body = $json->encode($payload);
    my $tmpfile = "/tmp/vision_req_$$.json";
    open(my $fh, '>:utf8', $tmpfile) or die "Cannot write $tmpfile: $!";
    print $fh $body;
    close $fh;

    my @curl = ('curl', '-sS', '--max-time', $timeout, '-X', 'POST',
                '-H', 'Content-Type: application/json', '-d', '@' . $tmpfile);
    push @curl, '-H', $auth_header if $auth_header;
    push @curl, '-o', '-', '-w', "\n%{http_code}\n", $url;

    open(my $pipe, '-|', @curl) or die "Failed to execute curl";
    local $/;
    my $all = <$pipe>;
    close $pipe;
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

        # Yandex Disk support: resolve public link to direct download
        if ($url =~ m{disk\.yandex\.(?:ru|com|by|kz|ee)}i || $url =~ m{yadi\.sk}i) {
            require URI::Escape;
            my $pub_key = URI::Escape::uri_escape($url);
            my $api = "https://cloud-api.yandex.net/v1/disk/public/resources/download?public_key=$pub_key";
            my $atmp = "/tmp/vision_yadisk_api_$$.json";
            system('curl', '-sS', '--max-time', '15', '-o', $atmp, $api);
            die "Yandex Disk API failed" unless -e $atmp && -s $atmp;
            open(my $afh, '<:utf8', $atmp) or die "Cannot read $atmp ($!)";
            local $/; my $abody = <$afh>; close $afh; unlink $atmp;
            my $adata = eval { $json->decode($abody) };
            die "Yandex Disk API: bad response" unless $adata && $adata->{href};
            my $exit = system('curl', '-sS', '-L', '--max-time', '120', '-o', $tmp, $adata->{href});
            die "Yandex Disk download failed (exit=$exit)" unless -e $tmp && -s $tmp;
        }
        else {
            my $exit = system('curl', '-sS', '-L', '--max-time', '60', '-o', $tmp, $url);
            die "URL download failed (exit=$exit): $url" unless -e $tmp && -s $tmp;
        }
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

# image_dir is where generated pictures are written. The default is a folder a person can find on
# their own; IMAGE_DIR moves it, IMAGE_BASE_URL turns the file name into a link for a folder that is
# published (a local folder has no address, and inventing one would be a lie).
sub image_dir {
    my $dir = $ENV{IMAGE_DIR};
    unless ($dir) {
        my $home = $ENV{HOME} // $ENV{USERPROFILE} // '.';
        $dir = "$home/Pictures/anytext";
    }
    mkdir $dir unless -d $dir;
    return $dir;
}

sub do_image_gen {
    my ($args) = @_;
    my $prompt = $args->{prompt} // '';
    die "Missing required: 'prompt'" unless $prompt =~ /\S/;
    my $model   = $args->{model} // $ENV{IMAGE_MODEL} // 'gpt-image-2';
    my $size    = $args->{size}  // $ENV{IMAGE_SIZE}  // '1024x1024';
    my $api_key = $ENV{OPENAI_API_KEY} or die "OPENAI_API_KEY not set for image generation";

    my $started = time;
    my ($status, $content) = _http_post_json(
        'https://api.openai.com/v1/images/generations',
        { model => $model, prompt => $prompt, n => 1, size => $size },
        "Authorization: Bearer $api_key",
        600,    # an image takes minutes, not seconds
    );
    die "OpenAI Images API error (HTTP $status)" unless $status eq '200';

    my $data = eval { $json->decode($content) };
    die "OpenAI Images API: bad response" unless $data;
    my $b64 = $data->{data}[0]{b64_json}
        or die "OpenAI Images API returned no image (only base64 output is supported)";

    my $dir  = image_dir();
    my $name = 'img_' . time . '.png';
    my $path = "$dir/$name";
    open(my $fh, '>:raw', $path) or die "Cannot write $path ($!)";
    print $fh decode_base64($b64);
    close $fh;

    my $result = {
        path    => $path,
        prompt  => $prompt,
        model   => $model,
        size    => $size,
        elapsed => time - $started,
    };
    my $base = $ENV{IMAGE_BASE_URL};
    $result->{url} = "$base/$name" if $base;
    return $result;
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
                                description => 'Model to use: gpt-4o-mini (OpenAI, default) for fast results on ordinary tasks; kimi-k2.7-code:cloud for a balance of speed and detail; deepseek-v4.1-flash:cloud for maximum detail.',
                            },
                        },
                    },
                },
                {
                    name        => 'image_gen',
                    description => 'Generate an image from a text prompt (OpenAI Images API) and save it as a PNG in IMAGE_DIR. Returns the local path of the file and, when the folder is published, a URL. In the answer put the returned path on a line of its own: the AnyText window then shows the picture and captions it with the collection and the file name. Add the URL only when the picture must be seen outside the window.',
                    inputSchema => {
                        type       => 'object',
                        properties => {
                            prompt => {
                                type        => 'string',
                                description => 'Text description of the image to generate',
                            },
                            model => {
                                type        => 'string',
                                description => 'Image model (default: gpt-image-2)',
                            },
                            size => {
                                type        => 'string',
                                description => 'Image size, e.g. 1024x1024 (default) or 1536x1024',
                            },
                        },
                        required => ['prompt'],
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
        elsif ($tool_name eq 'image_gen') {
            eval {
                my $result = do_image_gen($tool_args);
                respond($id, {
                    content => [
                        { type => 'text', text => $json->encode($result) },
                    ],
                });
            };
            if ($@) {
                my $err = $@;
                chomp $err;
                respond_error($id, -32603, "image_gen error: $err");
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
