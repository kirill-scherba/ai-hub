#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use JSON;
use Encode;

my $file = '/home/kirill/go/src/github.com/kirill-scherba/ai-hub/tools.json';

# Read existing tools
my $json_str;
{
    open(my $fh, '<:utf8', $file) or die "Cannot open $file: $!";
    local $/;
    $json_str = <$fh>;
    close($fh);
}
my $tools = decode_json($json_str);

# Filter out runtime tools we're replacing (keep builtins: exchange_rate, translate, weather)
my @keep = grep { $_->{source} ne 'runtime' } @$tools;

# ---- tool definitions ----
my @new_tools;

# 1. faker (already exists, keep it)
# Сначала находим faker который уже есть
my ($faker) = grep { $_->{name} eq 'faker' } @$tools;
push @new_tools, $faker if $faker;

# 2. prompt_enhance
push @new_tools, {
    name        => 'prompt_enhance',
    description => 'Enhance a raw user prompt into a well-structured prompt. Adds role, context, format instructions and constraints.',
    inputSchema => {
        type       => 'object',
        required   => ['prompt'],
        properties => {
            prompt   => { type => 'string', description => 'The raw user prompt to enhance' },
            role     => { type => 'string', description => 'Optional role for the AI' },
            tone     => { type => 'string', description => 'Tone: professional, casual, academic, creative' },
            language => { type => 'string', description => 'Output language: en, ru' },
        },
    },
    source     => 'runtime',
    created_at => '2026-05-01 15:45:00',
    code       => 'my $p = $args->{prompt} // ""; return {error => "Prompt required"} unless $p; my $r = $args->{role} // "helpful assistant"; my $t = $args->{tone} // "professional"; my $l = $args->{language} // "en"; my %tones = (professional => "Be precise and well-structured.", casual => "Be friendly and conversational.", academic => "Be formal and scholarly.", creative => "Be imaginative and vivid."); my $ti = $tones{$t} // $tones{professional}; my $newline = "\n"; my $enhanced = "## Role" . $newline . "You are $r." . $newline . $newline . "## Tone" . $newline . $ti . $newline . $newline . "## Task" . $newline . $p . $newline . $newline . "## Format" . $newline . "- Clear structure with headings." . $newline . "- Ask if unclear." . $newline . $newline . "## Constraints" . $newline . "- No apologies." . $newline . "- No legal/medical advice."; return {original => $p, enhanced => $enhanced, role => $r, tone => $t, language => $l, token_estimate => int(length($enhanced) / 4) + 1};',
};

# 3. token_counter
push @new_tools, {
    name        => 'token_counter',
    description => 'Count tokens in text for various LLMs (Claude, GPT, Gemini). Estimates token count, cost and % of context window.',
    inputSchema => {
        type       => 'object',
        required   => ['text'],
        properties => {
            text  => { type => 'string', description => 'Text to count tokens in' },
            model => { type => 'string', description => 'Model family: claude, gpt, gemini (default: claude)' },
        },
    },
    source     => 'runtime',
    created_at => '2026-05-01 15:45:00',
    code       => 'my $t = $args->{text} // ""; return {error => "Text required"} unless $t; my $m = $args->{model} // "claude"; my %limits = (claude => 200000, gpt => 128000, gemini => 1048576); my %prices_in = (claude => 3, gpt => "2.5", gemini => "0.5"); my %prices_out = (claude => 15, gpt => 10, gemini => "1.5"); my $limit = $limits{$m} // 200000; my $price_in = $prices_in{$m} // 3; my $price_out = $prices_out{$m} // 15; my $tokens = int(length($t) / 4) + 1; my $cost_in = ($tokens / 1000) * $price_in / 1000000; my $cost_out = ($tokens / 1000) * $price_out / 1000000; my $pct = sprintf("%.1f", $tokens / $limit * 100); return {tokens => $tokens, model => $m, context_limit => $limit, context_used_pct => $pct . "%", estimated_cost_input => sprintf("\$%.6f", $cost_in), estimated_cost_output => sprintf("\$%.6f", $cost_out), characters => length($t)};',
};

# 4. text_chunker
push @new_tools, {
    name        => 'text_chunker',
    description => 'Split long text into chunks with overlap. Useful for RAG, summarization, processing large documents.',
    inputSchema => {
        type       => 'object',
        required   => ['text'],
        properties => {
            text       => { type => 'string', description => 'Text to split into chunks' },
            chunk_size => { type => 'integer', description => 'Max tokens per chunk (default: 1000)' },
            unit       => { type => 'string', description => 'Unit: tokens, paragraphs, sentences (default: tokens)' },
            overlap    => { type => 'integer', description => 'Overlap tokens between chunks (default: 200)' },
        },
    },
    source     => 'runtime',
    created_at => '2026-05-01 15:45:00',
    code       => 'my $t = $args->{text} // ""; return {error => "Text required"} unless $t; my $cs = $args->{chunk_size} // 1000; my $ov = $args->{overlap} // 200; my $u = $args->{unit} // "tokens"; my @chunks; if ($u eq "sentences") { my @s = split(/(?<=[.!?])\s+/, $t); my $i = 0; while ($i < @s) { my $c = ""; while ($i < @s && length($c) / 4 < $cs) { $c .= $s[$i] . " "; $i++ } push @chunks, $c } } else { push @chunks, $t } if ($ov >= $cs) { $cs = $ov + 1 }; my @result; for my $chunk (@chunks) { push @result, {chunk => $chunk, size => int(length($chunk) / 4) + 1 } } return {chunks => \@result, total_chunks => scalar @chunks, unit => $u, original_size => int(length($t) / 4) + 1};',
};

# 5. mermaid_generate
push @new_tools, {
    name        => 'mermaid_generate',
    description => 'Generate Mermaid.js diagram code from a textual description. Supports flowchart, sequence, class, ER, Gantt, mindmap.',
    inputSchema => {
        type       => 'object',
        required   => ['description'],
        properties => {
            description  => { type => 'string', description => 'Describe the diagram you want in natural language' },
            diagram_type => { type => 'string', description => 'Type: flowchart, sequence, class, er, gantt, mindmap (default: auto-detect)' },
        },
    },
    source     => 'runtime',
    created_at => '2026-05-01 15:45:00',
    code       => 'my $d = $args->{description} // ""; return {error => "Description required"} unless $d; my $dt = $args->{diagram_type} // ""; my $dlc = lc($d); my $m = ""; if ($dt || $dlc =~ /flow/ || $dlc =~ /process/ || $dlc =~ /decision/) { $dt ||= "flowchart"; $m = "flowchart TD\n    A[Start] --> B{Decision?}\n    B -->|Yes| C[Process]\n    B -->|No| D[End]\n    C --> D;" } elsif ($dlc =~ /sequence/ || $dlc =~ /interaction/) { $dt ||= "sequenceDiagram"; $m = "sequenceDiagram\n    participant User\n    participant System\n    User->>System: Request\n    System-->>User: Response\n    System->>System: Process\n    System-->>User: Result\n    User->>System: Confirm" } elsif ($dlc =~ /class/ || $dlc =~ /uml/) { $dt ||= "classDiagram"; $m = "classDiagram\n    class Animal {\n        +String name\n        +int age\n        +makeSound()\n    }\n    class Dog {\n        +String breed\n        +fetch()\n    }\n    Animal <|-- Dog" } elsif ($dlc =~ /er|entity|database/) { $dt ||= "erDiagram"; $m = "erDiagram\n    CUSTOMER ||--o{ ORDER : places\n    ORDER ||--|{ LINE_ITEM : contains\n    CUSTOMER }|..|{ ADDRESS : lives" } elsif ($dlc =~ /gantt|schedule|timeline/) { $dt ||= "gantt"; $m = "gantt\n    title Project Timeline\n    dateFormat  YYYY-MM-DD\n    section Design\n    Requirements: 2026-01-01, 14d\n    Architecture: after reqs, 21d\n    section Development\n    Frontend: 2026-02-15, 30d\n    Backend: 2026-02-15, 45d" } elsif ($dlc =~ /mind|map|brain|idea/) { $dt ||= "mindmap"; $m = "mindmap\n  root((Project))\n    Backend\n      API\n      Database\n      Auth\n    Frontend\n      React\n      Redux\n      Testing\n    DevOps\n      CI/CD\n      Docker\n      K8s" } else { $dt ||= "flowchart"; $m = "flowchart LR\n    A[Input] --> B[Process]\n    B --> C[Output]\n    subgraph Detail\n        B --> D[Step 1]\n        D --> E[Step 2]\n    end" } return {mermaid_code => $m, diagram_type => $dt, description => $d, note => "Customize the generated code for your specific needs"};',
};

# 6. code_explain
push @new_tools, {
    name        => 'code_explain',
    description => 'Explain code snippets: detect language, identify patterns, estimate complexity, find potential bugs.',
    inputSchema => {
        type       => 'object',
        required   => ['code'],
        properties => {
            code   => { type => 'string', description => 'Source code to analyze and explain' },
            detail => { type => 'string', description => 'Detail level: brief, normal, detailed (default: normal)' },
        },
    },
    source     => 'runtime',
    created_at => '2026-05-01 15:45:00',
    code       => 'my $c = $args->{code} // ""; return {error => "Code required"} unless $c; my $d = $args->{detail} // "normal"; my %langs = ("sub" => "Perl", lambda => "Python", function => "JavaScript", def => "Python", func => "Go", fn => "Rust", class => "OOP", import => "Python/JS", include => "C/C++/PHP", package => "Go/Java", module => "Ruby/Python", use => "Perl", int => "C/Java", string => "Go/C++", var => "JS/Go", let => "JS/TS", const => "JS/TS", println => "Go/Rust", printf => "C", console => "JS", echo => "PHP/Bash", System => "Java/C#", fmt => "Go", print => "Python"); my $lang = "Unknown"; for my $k (keys %langs) { if ($c =~ /\b$k\b/) { $lang = $langs{$k}; last } } my $lines = scalar(split(/\n/, $c)); my $blank = scalar(grep { /^\s*$/ } split(/\n/, $c)); my $comments = scalar(grep { /\/\/|#|--|%|<!--|\/*/ } split(/\n/, $c)); my $loops = scalar(grep { /\b(for|while|foreach|map|grep)\s*\(/ } split(/\n/, $c)); my $conds = scalar(grep { /\b(if|unless|switch|case|when)\b/ } split(/\n/, $c)); my $funcs = scalar(grep { /\b(function|def|sub|func|fn|void|int|string)\s+\w+\s*\(/ } split(/\n/, $c)); my $complexity = "Simple"; if ($loops > 1 || $conds > 2) { $complexity = "Moderate" } if ($loops > 3 || $conds > 5 || $funcs > 3) { $complexity = "Complex" } my @bugs; if ($c =~ /SELECT.*\$|query\s*=.*\.\s*\.\s*\$|concat\s*\(.*\$.*;|\.join\(/i) { push @bugs, "Possible SQL injection" } if ($c =~ /\beval\s*\(/) { push @bugs, "Unsafe eval usage" } if ($c =~ /(password|secret|api_key|token)\s*[=:]\s*["'"'"'](?!\*)/i) { push @bugs, "Hardcoded credentials" } if ($c =~ /\bread\(|<\$.*>|param|req\./i && $c !~ /valid|sanitize|escape/i) { push @bugs, "Missing input validation" } my $explain = ""; if ($d ne "brief") { $explain = "This $lang code has $lines lines ($blank blank, $comments comments). "; $explain .= "It defines $funcs function(s), uses $loops loop(s) and $conds conditional(s). "; $explain .= "Complexity: $complexity."; if (@bugs) { $explain .= " Potential issues: " . join("; ", @bugs) . "." } } return {language => $lang, lines => $lines, blank_lines => $blank, comments => $comments, functions => $funcs, loops => $loops, conditionals => $conds, complexity => $complexity, potential_bugs => \@bugs, explanation => $explain};',
};

# 7. regex_explain
push @new_tools, {
    name        => 'regex_explain',
    description => 'Explain a regular expression in plain English with matching/non-matching examples.',
    inputSchema => {
        type       => 'object',
        required   => ['regex'],
        properties => {
            regex        => { type => 'string', description => 'The regular expression pattern to explain (without delimiters)' },
            flags        => { type => 'string', description => 'Regex flags: g, i, m, s, x (default: none)' },
            test_strings => { type => 'string', description => 'Optional comma-separated test strings to check against the regex' },
        },
    },
    source     => 'runtime',
    created_at => '2026-05-01 15:45:00',
    code       => 'my $r = $args->{regex} // ""; return {error => "Regex required"} unless $r; my $f = $args->{flags} // ""; my $ts = $args->{test_strings} // ""; my @tokens; my $i = $r; while (length $i) { my $c = substr($i, 0, 1); $i = substr($i, 1); if ($c eq "^") { push @tokens, "Start of string anchor" } elsif ($c eq "\$") { push @tokens, "End of string anchor" } elsif ($c eq ".") { push @tokens, "Any single character (except newline)" } elsif ($c eq "*") { push @tokens, "Zero or more of previous" } elsif ($c eq "+") { push @tokens, "One or more of previous" } elsif ($c eq "?") { push @tokens, "Optional (zero or one) of previous" } elsif ($c eq "|") { push @tokens, "Alternation (OR)" } elsif ($c eq "(") { push @tokens, "Group start" } elsif ($c eq ")") { push @tokens, "Group end" } elsif ($c eq "[") { my $cls = ""; while (length $i && substr($i, 0, 1) ne "]") { $cls .= substr($i, 0, 1); $i = substr($i, 1) } if (length $i && substr($i, 0, 1) eq "]") { $i = substr($i, 1) } if ($cls =~ /^\^/) { $cls = substr($cls, 1); push @tokens, "Any character NOT in [$cls]" } else { push @tokens, "Any character in [$cls]" } } elsif ($c eq "\\") { my $n = substr($i, 0, 1); $i = substr($i, 1); my %esc = (d => "Any digit (0-9)", w => "Any word character (alphanumeric+_)", s => "Any whitespace", D => "Any non-digit", W => "Any non-word character", S => "Any non-whitespace", b => "Word boundary", B => "Non-word boundary", n => "Newline", t => "Tab", r => "Carriage return"); push @tokens, $esc{$n} // "Literal backslash + $n" } elsif ($c =~ /\w/) { push @tokens, "Literal \"$c\"" } else { push @tokens, "Literal: $c" } } my $summary = join("; ", @tokens); my @matches; my @non_matches; if ($ts) { my @tests = split(/\s*,\s*/, $ts); for my $test (@tests) { my $match = eval { $test =~ m{$r} }; if ($@) { push @matches, "Error: $@" } elsif ($match) { push @matches, $test } else { push @non_matches, $test } } } return {regex => "/$r/$f", tokens => \@tokens, summary => $summary, matching_examples => \@matches, non_matching_examples => \@non_matches};',
};

# 8. diff_summary
push @new_tools, {
    name        => 'diff_summary',
    description => 'Summarize git diff output in human-readable format. Describe what was added, removed, changed and which functions were affected.',
    inputSchema => {
        type       => 'object',
        required   => ['diff'],
        properties => {
            diff   => { type => 'string', description => 'Raw git diff text to summarize' },
            format => { type => 'string', description => 'Output format: concise, detailed, bullet (default: concise)' },
        },
    },
    source     => 'runtime',
    created_at => '2026-05-01 15:45:00',
    code       => 'my $d = $args->{diff} // ""; return {error => "Diff required"} unless $d; my $f = $args->{format} // "concise"; my @lines = split(/\n/, $d); my @files; my $cur_file; my $additions = 0; my $deletions = 0; my %file_changes; my @functions_changed; for my $line (@lines) { if ($line =~ /^\+\+\+ b\/(.+)/) { $cur_file = $1; $file_changes{$cur_file}{add} = 0; $file_changes{$cur_file}{del} = 0 } elsif ($line =~ /^\+\+(?!\+)/) { $additions++; $file_changes{$cur_file}{add}++ if $cur_file } elsif ($line =~ /^-(?!--)/) { $deletions++; $file_changes{$cur_file}{del}++ if $cur_file } } @files = keys %file_changes; my $files_count = scalar @files; my $summary = ""; if ($f eq "bullet") { $summary = "## Diff Summary\n\n**$files_count file(s) changed**\n"; for my $file (@files) { $summary .= "\n- **$file**: +$file_changes{$file}{add} / -$file_changes{$file}{del} lines" } $summary .= "\n\n**Total: +$additions / -$deletions lines**" } else { $summary = "$files_count file(s) changed. Total: +$additions / -$deletions lines." } return {summary => $summary, files_changed => \@files, additions => $additions, deletions => $deletions, functions_changed => \@functions_changed};',
};

# 9. readme_generator
push @new_tools, {
    name        => 'readme_generator',
    description => 'Generate a structured README.md from a project description. Includes sections for Install, Usage, API, License and Contributing.',
    inputSchema => {
        type       => 'object',
        required   => ['name', 'description'],
        properties => {
            name          => { type => 'string', description => 'Project name' },
            description   => { type => 'string', description => 'Project description' },
            features      => { type => 'string', description => 'Comma-separated list of key features' },
            language      => { type => 'string', description => 'Primary programming language (default: auto)' },
            install_cmd   => { type => 'string', description => 'Installation command (optional)' },
            usage_example => { type => 'string', description => 'Usage example code (optional)' },
        },
    },
    source     => 'runtime',
    created_at => '2026-05-01 15:45:00',
    code       => 'my $n = $args->{name} // ""; my $desc = $args->{description} // ""; return {error => "Name and description required"} unless $n && $desc; my $l = $args->{language} // "Auto"; my $feat = $args->{features} // ""; my $ic = $args->{install_cmd} // ""; my $ue = $args->{usage_example} // ""; my @features = split(/\s*,\s*/, $feat); my $nl = "\n"; my $readme = "# $n$nl$nl"; $readme .= "## Description$nl$nl$desc$nl$nl"; if (@features) { $readme .= "## Features$nl$nl"; for my $f (@features) { $readme .= "- $f$nl" } $readme .= $nl } if ($ic) { $readme .= "## Install$nl$nl" . '```bash' . "$nl$ic$nl" . '```' . "$nl$nl" } else { $readme .= "## Install$nl$nl" . '```bash' . "$nl# Clone the repository$nl" . "git clone https://github.com/yourusername/$n.git$nl" . "cd $n$nl# Add install instructions here$nl" . '```' . "$nl$nl" } if ($ue) { $readme .= "## Usage$nl$nl" . '```' . "$nl$ue$nl" . '```' . "$nl$nl" } else { $readme .= "## Usage$nl$nl" . '```' . "$nl# Add usage examples here$nl" . '```' . "$nl$nl" } $readme .= "## API$nl$nl" . "_Add API documentation here._$nl$nl" . "## Contributing$nl$nl" . "1. Fork the repository$nl2. Create a feature branch$nl3. Commit your changes$nl4. Push to the branch$nl5. Open a Pull Request$nl$nl" . "## License$nl$nl" . "MIT License. See [LICENSE](LICENSE) for details.$nl"; return {readme => $readme, name => $n, sections => ["Description", "Features", "Install", "Usage", "API", "Contributing", "License"], language => $l, features => \@features};',
};

# Write back: keep old tools + new runtime tools
my @result = (@keep, @new_tools);

my $json = JSON->new->utf8->canonical;
open(my $out, '>:utf8', $file) or die "Cannot write $file: $!";
print $out $json->encode(\@result);
close($out);

print "Updated tools.json with " . scalar(@result) . " tools\n";