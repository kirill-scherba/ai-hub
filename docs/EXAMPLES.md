# Tool Generation Examples

This document shows real examples of MCP tools generated at runtime using `tool_generate`. Each example includes the full Perl code, JSON schema, and a usage demonstration.

## 1. convert_units — Convert Between Measurement Units

Generated at runtime to handle length, weight, temperature, and volume conversions.

### Schema

```json
{
  "name": "convert_units",
  "description": "Convert between measurement units: length, weight, temperature, volume",
  "inputSchema": {
    "type": "object",
    "required": ["value", "from", "to"],
    "properties": {
      "value": { "type": "number", "description": "The value to convert" },
      "from":  { "type": "string", "description": "Source unit code" },
      "to":    { "type": "string", "description": "Target unit code" }
    }
  }
}
```

### Perl Code

```perl
my ($v, $f, $t) = @{$args}{qw(value from to)};
die unless defined $v && $f && $t;

# Category detection
my %c = (
  mile=>1, km=>1, m=>1, ft=>1, in=>1, yard=>1,
  kg=>2, g=>2, lb=>2, oz=>2,
  C=>3, F=>3, K=>3,
  L=>4, mL=>4, gal=>4, qt=>4, pt=>4, cup=>4, fl_oz=>4
);
die "bad $f" unless $c{$f};
die "mismatch" unless $c{$f} eq $c{$t};

# Length conversions
if ($c{$f} == 1) {
  my %m = (mile=>1609.344, km=>1000, m=>1, ft=>0.3048, in=>0.0254, yard=>0.9144);
  return { result => $v * $m{$f} / $m{$t} + 0.0, ... };
}

# Temperature conversions (formula-based)
if ($c{$f} == 3) {
  my $k = $f eq 'K' ? $v : $f eq 'C' ? $v + 273.15 : ($v - 32) * 5/9 + 273.15;
  my $r = $t eq 'K' ? $k : $t eq 'C' ? $k - 273.15 : ($k - 273.15) * 9/5 + 32;
  return { result => $r + 0.0, ... };
}
```

### Usage

```
Input:  { "value": 100, "from": "km", "to": "mile" }
Output: { "result": 62.1371, "category": "length" }
```

---

## 2. token_counter — Estimate LLM Token Count

Estimates tokens, cost, and context window usage for Claude, GPT, and Gemini.

### Schema

```json
{
  "name": "token_counter",
  "description": "Count tokens for Claude, GPT, Gemini — estimate cost and context usage",
  "inputSchema": {
    "type": "object",
    "required": ["text"],
    "properties": {
      "text":  { "type": "string", "description": "Text to count tokens in" },
      "model": { "type": "string", "description": "Model family: claude, gpt, gemini" }
    }
  }
}
```

### Perl Code

```perl
my $t = $args->{text} // "";
return { error => "Text required" } unless $t;
my $m = $args->{model} // "claude";

my %limits    = (claude => 200000, gpt => 128000, gemini => 1048576);
my %prices_in = (claude => 3, gpt => 2.5, gemini => 0.5);
my %prices_out= (claude => 15, gpt => 10, gemini => 1.5);

my $limit    = $limits{$m} // 200000;
my $price_in = $prices_in{$m} // 3;
my $price_out= $prices_out{$m} // 15;

my $tokens  = int(length($t) / 4) + 1;
my $cost_in = ($tokens / 1000) * $price_in / 1000000;
my $pct     = sprintf("%.1f", $tokens / $limit * 100);

return {
  tokens               => $tokens,
  model                => $m,
  context_limit        => $limit,
  context_used_pct     => $pct . "%",
  estimated_cost_input => sprintf("$%.6f", $cost_in),
  characters           => length($t),
};
```

### Usage

```
Input:  { "text": "Hello, world! This is a test.", "model": "claude" }
Output: { "tokens": 9, "context_used_pct": "0.0%",
          "estimated_cost_input": "$0.000027" }
```

---

## 3. deploy_check — URL Deployment Health Check

Checks HTTP status, response time, SSL certificate expiry, robots.txt and sitemap.xml.

### Schema

```json
{
  "name": "deploy_check",
  "description": "Check deployment health: HTTP status, response time, SSL, robots.txt, sitemap.xml",
  "inputSchema": {
    "type": "object",
    "required": ["url"],
    "properties": {
      "url": { "type": "string", "description": "URL to check" }
    }
  }
}
```

### Perl Code

```perl
my $url = $args->{url};
$url =~ s|/+$||;
$url = 'https://' . $url unless $url =~ m{^https?://}i;

# HTTP Status & Response Time
my $http_info = _safe_curl_get_code_and_time($url, 15);
my ($http_code, $resp_time) = split(':', $http_info);
my $rt = defined $resp_time ? sprintf('%.0f', $resp_time * 1000) : '-';

# SSL Expiry
my $ssl_expiry = '-';
my $verbose = _safe_curl_verbose($url, 12);
if ($verbose =~ /expire date:\s*(.+)/i) { $ssl_expiry = $1; }

# robots.txt & sitemap.xml
my $robots_code  = _safe_curl_get_http_code($url . '/robots.txt', 8);
my $sitemap_code = _safe_curl_get_http_code($url . '/sitemap.xml', 8);

return {
  url              => $url,
  http_status      => $http_code + 0,
  response_time_ms => $rt,
  ssl_expiry       => $ssl_expiry,
  robots_txt       => $robots_code eq '200' ? 'YES' : 'no',
  sitemap_xml      => $sitemap_code eq '200' ? 'YES' : 'no',
};
```

### Usage

```
Input:  { "url": "https://example.com" }
Output: { "http_status": 200, "response_time_ms": "120",
          "ssl_expiry": "Jul 20 23:59:59 2026 GMT" }
```

---

## 4. code_explain — Analyze and Explain Code Snippets

Detects language, identifies patterns, estimates complexity, and flags potential bugs.

### Schema

```json
{
  "name": "code_explain",
  "description": "Explain code: detect language, patterns, complexity, bugs",
  "inputSchema": {
    "type": "object",
    "required": ["code"],
    "properties": {
      "code":   { "type": "string", "description": "Source code to analyze" },
      "detail": { "type": "string", "description": "Detail level: brief/normal/detailed" }
    }
  }
}
```

### Perl Code

```perl
my $c = $args->{code} // "";
return { error => "Code required" } unless $c;
my $d = $args->{detail} // "normal";

# Language detection
my %langs = (
  sub     => "Perl",    lambda  => "Python",   function => "JavaScript",
  def     => "Python",  func    => "Go",        fn       => "Rust",
  int     => "C/Java",  var     => "JS/Go",     const    => "JS/TS",
  println => "Go/Rust", printf  => "C",         echo     => "PHP/Bash",
);
my $lang = "Unknown";
for my $k (keys %langs) {
  if ($c =~ /\b$k\b/) { $lang = $langs{$k}; last }
}

# Complexity analysis
my $lines    = scalar(split(/\n/, $c));
my $loops    = scalar(grep { /\b(for|while|foreach)\s*\(/ } split(/\n/, $c));
my $conds    = scalar(grep { /\b(if|unless|switch|case)\b/ } split(/\n/, $c));
my $funcs    = scalar(grep { /\b(function|def|sub|func|fn)\s+\w+\s*\(/ } split(/\n/, $c));

my $complexity = "Simple";
$complexity = "Moderate" if ($loops > 1 || $conds > 2);
$complexity = "Complex"  if ($loops > 3 || $conds > 5 || $funcs > 3);

# Bug detection
my @bugs;
push @bugs, "Possible SQL injection" if $c =~ /SELECT.*\$/i;
push @bugs, "Hardcoded credentials" if $c =~ /(password|secret|api_key)\s*[=:]\s*["'](?!\*)/i;

return {
  language        => $lang,
  lines           => $lines,
  complexity      => $complexity,
  potential_bugs  => \@bugs,
  explanation     => "This $lang code has $lines lines. Complexity: $complexity.",
};
```

### Usage

```
Input:  { "code": "def hello(name):\n    print(f'Hello, {name}')\n    return True" }
Output: { "language": "Python", "lines": 3, "complexity": "Simple" }
```

---

## Generation Pattern

All these tools were created by sending a request to the AI assistant like:

> "Use `tool_generate` to create a tool called `<name>` that takes `<inputs>` and returns `<outputs>`."

The AI constructs the Perl code, the schema, and calls `tool_generate`. The hub:

1. Validates the tool name (alphanumeric + underscores)
2. Checks the code for unauthorized modules (whitelist only)
3. Compiles the code inside `Safe->new()` sandbox
4. Registers it in the tool registry
5. Persists it to `tools.json`
6. Sends a `tools/list_changed` notification

The tool is immediately available for use — no restart required.

## Exporting and Sharing

Generated tools can be exported as JSON:

```json
{
  "name": "my_custom_tool",
  "description": "Description here",
  "inputSchema": { ... },
  "code": "perl code here",
  "source": "runtime",
  "created_at": "2026-05-01 19:58:51"
}
```

This JSON can be:
- **Shared** with other AI Hub instances via `tool_import`
- **Published** to the Hub Server via `hub_publish` for semantic search
- **Stored** in version control for reproducibility