#!/usr/bin/env perl
# =============================================================================
# json_tool & hash_generate — MCP tools for JSON operations and hashing
#
# Each section contains:
#   1. Tool metadata (name, description, inputSchema)
#   2. Perl code ready for tool_generate
# =============================================================================
use strict;
use warnings;

# ===========================================================================
# Tool 1/2: json_tool
# JSON operations: format, validate, compress, diff
# Uses _safe_json_decode / _safe_json_encode (shared helpers)
# ===========================================================================
# Metadata:
#   name: json_tool
#   description: JSON operations: format, validate, compress, diff
#   inputSchema: { operation, json?, json2?, indent? }
#
our $TOOL_json_tool_code = <<'PERL_CODE';
my $op     = $args->{operation} or return { error => "Missing required parameter: operation" };
my $json   = $args->{json};
my $json2  = $args->{json2};
my $indent = $args->{indent} // 2;

if ($op eq 'format') {
    return { error => "Missing required for format: json" } unless defined $json;
    my $decoded = _safe_json_decode($json);
    return { error => "Invalid JSON: " . $decoded->{_error}, operation => 'format' } if (ref $decoded eq 'HASH' && exists $decoded->{_error});
    my $formatted = _safe_json_encode($decoded, 1);
    return { result => $formatted, operation => 'format', indent => $indent };
}

if ($op eq 'validate') {
    return { error => "Missing required for validate: json" } unless defined $json;
    my $decoded = _safe_json_decode($json);
    my $valid = !(ref $decoded eq 'HASH' && exists $decoded->{_error});
    my $err = $valid ? undef : $decoded->{_error};
    return { valid => ($valid ? 1 : 0), error => $err, operation => 'validate' };
}

if ($op eq 'compress') {
    return { error => "Missing required for compress: json" } unless defined $json;
    my $decoded = _safe_json_decode($json);
    return { error => "Invalid JSON: " . $decoded->{_error}, operation => 'compress' } if (ref $decoded eq 'HASH' && exists $decoded->{_error});
    my $compressed = _safe_json_encode($decoded, 0);
    chomp $compressed;
    my $orig_len = length($json);
    my $comp_len = length($compressed);
    my $pct = $orig_len > 0 ? sprintf("%.1f", (1 - $comp_len / $orig_len) * 100) : "0.0";
    return { result => $compressed, original_size => $orig_len, compressed_size => $comp_len, compression_pct => $pct, operation => 'compress' };
}

if ($op eq 'diff') {
    return { error => "Missing required for diff: json and json2" } unless defined $json && defined $json2;
    my $d1 = _safe_json_decode($json);
    return { error => "First JSON invalid: " . $d1->{_error}, operation => 'diff' } if (ref $d1 eq 'HASH' && exists $d1->{_error});
    my $d2 = _safe_json_decode($json2);
    return { error => "Second JSON invalid: " . $d2->{_error}, operation => 'diff' } if (ref $d2 eq 'HASH' && exists $d2->{_error});
    my $json1_str = _safe_json_encode($d1, 0);
    my $json2_str = _safe_json_encode($d2, 0);
    if ($json1_str eq $json2_str) {
        return { identical => 1, operation => 'diff' };
    }
    return { identical => 0, operation => 'diff', left => _safe_json_encode($d1, 1), right => _safe_json_encode($d2, 1) };
}

return { error => "Unknown operation: $op. Supported: format, validate, compress, diff" };
PERL_CODE

our $TOOL_json_tool_meta = {
    name        => 'json_tool',
    description => 'JSON operations: format (pretty-print), validate (syntax check), compress (minify), diff (compare two JSONs). Uses JSON::PP.',
    inputSchema => {
        type       => 'object',
        required   => ['operation'],
        properties => {
            operation => {
                type        => 'string',
                enum        => ['format', 'validate', 'compress', 'diff'],
                description => 'JSON operation to perform',
            },
            json => {
                type        => 'string',
                description => 'JSON string to operate on (required for format, validate, compress)',
            },
            json2 => {
                type        => 'string',
                description => 'Second JSON string (required for diff)',
            },
            indent => {
                type        => 'integer',
                description => 'Indentation spaces for format (default: 2)',
            },
        },
    },
};

# ===========================================================================
# Tool 2/2: hash_generate
# Hash generation: md5, sha1, sha256, sha512
# Uses Digest::MD5 and Digest::SHA (both Safe-whitelisted)
# ===========================================================================
# Metadata:
#   name: hash_generate
#   description: Generate hash digests (md5/sha1/sha256/sha512)
#   inputSchema: { text, algorithm? }
#
our $TOOL_hash_generate_code = <<'PERL_CODE';
my $text      = $args->{text} or die "Missing required parameter: text";
my $algorithm = $args->{algorithm} // 'sha256';

use Digest::MD5;
use Digest::SHA;

my $digest_hex;
if ($algorithm eq 'md5') {
    $digest_hex = md5_hex($text);
} elsif ($algorithm eq 'sha1') {
    $digest_hex = sha1_hex($text);
} elsif ($algorithm eq 'sha256') {
    $digest_hex = sha256_hex($text);
} else {
    $digest_hex = sha512_hex($text);
}

return {
    algorithm     => $algorithm,
    digest_hex    => $digest_hex,
    digest_length => length($digest_hex) * 4,
    input_size    => length($text),
};
PERL_CODE

our $TOOL_hash_generate_meta = {
    name        => 'hash_generate',
    description => 'Generate hash digests for text. Supports md5, sha1, sha256, sha512. Uses Digest::MD5 and Digest::SHA.',
    inputSchema => {
        type       => 'object',
        required   => ['text'],
        properties => {
            text => {
                type        => 'string',
                description => 'Text content to hash',
            },
            algorithm => {
                type        => 'string',
                enum        => ['md5', 'sha1', 'sha256', 'sha512'],
                description => 'Hash algorithm (default: sha256)',
            },
        },
    },
};

# ===========================================================================
# Public API — returns array of tool definitions for generate-all-tools.pl
# ===========================================================================
sub get_json_hash_tools {
    return [
        {
            name        => $TOOL_json_tool_meta->{name},
            description => $TOOL_json_tool_meta->{description},
            inputSchema => $TOOL_json_tool_meta->{inputSchema},
            code        => $TOOL_json_tool_code,
        },
        {
            name        => $TOOL_hash_generate_meta->{name},
            description => $TOOL_hash_generate_meta->{description},
            inputSchema => $TOOL_hash_generate_meta->{inputSchema},
            code        => $TOOL_hash_generate_code,
        },
    ];
}

1; # End of JSON & Hash tools package
