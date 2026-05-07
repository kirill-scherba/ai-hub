#!/usr/bin/env perl
# =============================================================================
# token-counter-mcp — MCP server for counting tokens in text
#
# Approximate token counting for various LLM models (gpt-4o, claude, gemini).
# Uses character-based heuristics: ~4 chars/token for GPT, ~3.5 for Claude.
# =============================================================================

use strict;
use warnings;
use utf8;
use JSON;
use POSIX qw(strftime);

binmode(STDIN,  ":utf8");
binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

my $json = JSON->new->allow_nonref;

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

sub log_message {
    my ($msg) = @_;
    my $ts = strftime("%Y-%m-%d %H:%M:%S", localtime);
    print STDERR "[$ts] $msg\n";
    STDERR->flush();
}

# ---------------------------------------------------------------------------
# Token counter logic
# ---------------------------------------------------------------------------
sub count_tokens {
    my ($text, $model) = @_;
    $model //= 'gpt-4o';

    my $char_count = length($text);
    my @words = split /\s+/, $text;
    my $word_count = scalar @words;

    my $token_estimate;
    if ($model =~ /claude/i) {
        $token_estimate = int($char_count / 3.5 + 0.5);
    } elsif ($model =~ /gemini/i) {
        $token_estimate = int($char_count / 4 + 0.5);
    } else {
        $token_estimate = int($char_count / 4 + 0.5);
    }

    $token_estimate = 1 if $token_estimate < 1;
    $word_count = 1 if $word_count < 1;

    return {
        text_length_chars => $char_count,
        word_count        => $word_count,
        token_estimate    => $token_estimate,
        model             => $model,
    };
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
log_message("token-counter-mcp server started");

# Send initialized notification
my $init_notif = { jsonrpc => "2.0", method => "initialized" };
print $json->encode($init_notif) . "\n";
STDOUT->flush();

LINE: while (my $line = <STDIN>) {
    chomp $line;
    next LINE unless $line && $line =~ /\S/;

    log_message("Received: $line");

    my $msg = eval { $json->decode($line) };
    if ($@ || !$msg) {
        log_message("Invalid JSON: $@");
        next LINE;
    }

    my $id     = $msg->{id};
    my $method = $msg->{method} // '';
    my $params = $msg->{params} // {};

    # Handle notifications (no id)
    if (!defined $id) {
        log_message("Notification: $method");
        next LINE;
    }

    if ($method eq 'initialize') {
        respond($id, {
            protocolVersion => '2024-11-05',
            capabilities    => { tools => {} },
            serverInfo      => { name => 'token-counter-mcp', version => '0.1.0' },
        });
        log_message("Initialized");
    }
    elsif ($method eq 'ping') {
        respond($id, {});
    }
    elsif ($method eq 'tools/list') {
        respond($id, {
            tools => [
                {
                    name        => "token_counter",
                    description => "Count tokens in text using approximate estimation for various LLM models (gpt-4o, claude, gemini).",
                    inputSchema => {
                        type       => "object",
                        properties => {
                            text => {
                                type        => "string",
                                description => "The text to count tokens in.",
                            },
                            model => {
                                type        => "string",
                                description => "Model name for token estimation (gpt-4o, claude, gemini). Default: gpt-4o.",
                            },
                        },
                        required => ["text"],
                    },
                },
            ],
        });
        log_message("Sent tool list");
    }
    elsif ($method eq 'tools/call') {
        my $tool_name = $params->{name} // '';
        my $tool_args = $params->{arguments} // {};

        log_message("Executing tool: $tool_name");

        if ($tool_name eq 'token_counter') {
            my $text  = $tool_args->{text}  or do {
                respond_error($id, -32602, "Missing required parameter: 'text'");
                next LINE;
            };
            my $model = $tool_args->{model} // 'gpt-4o';

            my $result = count_tokens($text, $model);

            respond($id, {
                content => [
                    { type => "text", text => $json->encode({ status => "success", data => $result }) },
                ],
            });
            log_message("token_counter executed successfully");
        } else {
            respond_error($id, -32601, "Method not found: $tool_name");
        }
    }
    else {
        log_message("Unknown method: $method");
        respond_error($id, -32601, "Method not found: $method");
    }
}

log_message("token-counter-mcp server stopped");