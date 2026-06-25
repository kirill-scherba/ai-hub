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

sub do_vision_analyze {
    my ($args) = @_;
    my $url      = $args->{url}      // '';
    my $file_path = $args->{file_path} // '';
    my $question = $args->{question} // 'Describe this image in detail in Russian. What do you see?';
    my $model    = $ENV{VISION_MODEL} // 'gpt-4o-mini';

    my $api_key = $ENV{OPENAI_API_KEY} or die "OPENAI_API_KEY not set";

    # Resolve image source: file_path takes priority over url
    my $image_url;
    if ($file_path) {
        open(my $fh, '<:raw', $file_path) or die "Cannot read file: $file_path ($!)";
        local $/;
        my $data = <$fh>;
        close $fh;
        my $b64 = encode_base64($data, '');
        my $ext = $file_path =~ /\.(\w+)$/ ? lc($1) : 'png';
        my %mime = (png => 'image/png', jpg => 'image/jpeg', jpeg => 'image/jpeg',
                    webp => 'image/webp', gif => 'image/gif', bmp => 'image/bmp',
                    tiff => 'image/tiff', tif => 'image/tiff');
        my $mime = $mime{$ext} // 'image/png';
        $image_url = "data:$mime;base64,$b64";
    } elsif ($url) {
        $image_url = $url;
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

    # HTTP POST via curl
    my ($content, $status);
    if (open(my $fh, '-|', 'curl', '-sS', '--max-time', '60',
             '-X', 'POST',
             '-H', 'Content-Type: application/json',
             '-H', "Authorization: Bearer $api_key",
             '-d', $body,
             '-o', '-', '-w', "\n%{http_code}\n",
             'https://api.openai.com/v1/chat/completions')) {
        local $/;
        my $all = <$fh>;
        close $fh;
        utf8::decode($all);
        my @parts = split /\n/, $all;
        $status  = pop @parts;
        $content = join("\n", @parts);
    } else {
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
