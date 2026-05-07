#!/usr/bin/env perl
# =============================================================================
# GitHub Tools Package — 12 MCP tools for GitHub API integration
#
# Each section contains:
#   1. Tool metadata (name, description, inputSchema)
#   2. Perl code ready for tool_generate
#
# All tools call _github_api($method, $path, $json_body_string)
# which is a shared helper from generative-mcp-hub.pl (Safe sandbox).
# Authentication via $ENV{GITHUB_TOKEN} — token stays server-side.
# =============================================================================
use strict;
use warnings;

# ===========================================================================
# Tool 1/12: github_issue_create
# Create a new issue in a GitHub repository.
# GitHub API: POST /repos/{owner}/{repo}/issues
# ===========================================================================
# Metadata:
#   name: github_issue_create
#   description: Create a new GitHub issue in a repository
#   inputSchema: { owner, repo, title, body?, labels?[]?, assignees?[]? }
#
our $TOOL_github_issue_create_code = <<'PERL_CODE';
my $owner    = $args->{owner}    or die "Missing required: owner";
my $repo     = $args->{repo}     or die "Missing required: repo";
my $title    = $args->{title}    or die "Missing required: title";
my $body     = $args->{body}     // '';
my $labels   = $args->{labels}   // undef;
my $assignees = $args->{assignees} // undef;

my %payload = (title => $title, body => $body);
$payload{labels}    = $labels    if $labels;
$payload{assignees} = $assignees if $assignees;

my $body_str = $main::json_pp_decoder->encode(\%payload);
my $res = _github_api("POST", "/repos/$owner/$repo/issues", $body_str);

if ($res->{success}) {
    my $issue = $res->{data};
    return {
        issue_number => $issue->{number},
        issue_url    => $issue->{html_url},
        state        => $issue->{state},
        title        => $issue->{title},
        created_at   => $issue->{created_at},
    };
}
die "GitHub API error: " . ($res->{reason} // "HTTP $res->{status}");
PERL_CODE

# ===========================================================================
# Tool 2/12: github_issue_list
# List issues in a GitHub repository with optional filters.
# GitHub API: GET /repos/{owner}/{repo}/issues
# ===========================================================================
# Metadata:
#   name: github_issue_list
#   description: List GitHub issues in a repository with optional filters
#   inputSchema: { owner, repo, state?("open","closed","all"), labels?, limit? }
#
our $TOOL_github_issue_list_code = <<'PERL_CODE';
my $owner  = $args->{owner}  or die "Missing required: owner";
my $repo   = $args->{repo}   or die "Missing required: repo";
my $state  = $args->{state}  // "open";
my $labels = $args->{labels} // undef;
my $limit  = $args->{limit}  // 30;

my $path = "/repos/$owner/$repo/issues?state=$state&per_page=$limit&sort=created&direction=desc";
$path .= "&labels=" . join(",", ref $labels ? @$labels : ($labels)) if $labels;

my $res = _github_api("GET", $path);
if ($res->{success}) {
    my @issues;
    for my $issue (@{$res->{data} // []}) {
        push @issues, {
            number    => $issue->{number},
            title     => $issue->{title},
            state     => $issue->{state},
            url       => $issue->{html_url},
            labels    => [map { $_->{name} } @{$issue->{labels} // []}],
            created_at => $issue->{created_at},
            updated_at => $issue->{updated_at},
        };
    }
    return { issues => \@issues, count => scalar @issues };
}
die "GitHub API error: " . ($res->{reason} // "HTTP $res->{status}");
PERL_CODE

# ===========================================================================
# Tool 3/12: github_issue_get
# Get detailed information about a specific GitHub issue.
# GitHub API: GET /repos/{owner}/{repo}/issues/{issue_number}
# ===========================================================================
# Metadata:
#   name: github_issue_get
#   description: Get details of a specific GitHub issue
#   inputSchema: { owner, repo, issue_number }
#
our $TOOL_github_issue_get_code = <<'PERL_CODE';
my $owner  = $args->{owner}  or die "Missing required: owner";
my $repo   = $args->{repo}   or die "Missing required: repo";
my $number = $args->{issue_number} or die "Missing required: issue_number";

my $res = _github_api("GET", "/repos/$owner/$repo/issues/$number");
if ($res->{success}) {
    my $issue = $res->{data};
    return {
        number       => $issue->{number},
        title        => $issue->{title},
        body         => $issue->{body} // '',
        state        => $issue->{state},
        url          => $issue->{html_url},
        labels       => [map { $_->{name} } @{$issue->{labels} // []}],
        assignees    => [map { $_->{login} } @{$issue->{assignees} // []}],
        created_at   => $issue->{created_at},
        updated_at   => $issue->{updated_at},
        closed_at    => $issue->{closed_at} // undef,
        comments_count => $issue->{comments} // 0,
    };
}
die "GitHub API error: " . ($res->{reason} // "HTTP $res->{status}");
PERL_CODE

# ===========================================================================
# Tool 4/12: github_issue_update
# Update an existing GitHub issue (title, body, state, labels, assignees).
# GitHub API: PATCH /repos/{owner}/{repo}/issues/{issue_number}
# ===========================================================================
# Metadata:
#   name: github_issue_update
#   description: Update a GitHub issue (title, body, state, labels, assignees)
#   inputSchema: { owner, repo, issue_number, title?, body?, state?, labels?[]?, assignees?[]? }
#
our $TOOL_github_issue_update_code = <<'PERL_CODE';
my $owner    = $args->{owner}    or die "Missing required: owner";
my $repo     = $args->{repo}     or die "Missing required: repo";
my $number   = $args->{issue_number} or die "Missing required: issue_number";

my %payload;
$payload{title}     = $args->{title}     if defined $args->{title};
$payload{body}      = $args->{body}      if defined $args->{body};
$payload{state}     = $args->{state}     if defined $args->{state};
$payload{labels}    = $args->{labels}    if defined $args->{labels};
$payload{assignees} = $args->{assignees} if defined $args->{assignees};

die "Nothing to update" unless scalar keys %payload;

my $body_str = $main::json_pp_decoder->encode(\%payload);
my $res = _github_api("PATCH", "/repos/$owner/$repo/issues/$number", $body_str);
if ($res->{success}) {
    return {
        issue_number => $res->{data}{number},
        title        => $res->{data}{title},
        state        => $res->{data}{state},
        updated_at   => $res->{data}{updated_at},
    };
}
die "GitHub API error: " . ($res->{reason} // "HTTP $res->{status}");
PERL_CODE

# ===========================================================================
# Tool 5/12: github_issue_add_comment
# Add a comment to an existing GitHub issue.
# GitHub API: POST /repos/{owner}/{repo}/issues/{issue_number}/comments
# ===========================================================================
# Metadata:
#   name: github_issue_add_comment
#   description: Add a comment to a GitHub issue
#   inputSchema: { owner, repo, issue_number, body }
#
our $TOOL_github_issue_add_comment_code = <<'PERL_CODE';
my $owner  = $args->{owner}  or die "Missing required: owner";
my $repo   = $args->{repo}   or die "Missing required: repo";
my $number = $args->{issue_number} or die "Missing required: issue_number";
my $body   = $args->{body}   or die "Missing required: body";

my $body_str = $main::json_pp_decoder->encode({ body => $body });
my $res = _github_api("POST", "/repos/$owner/$repo/issues/$number/comments", $body_str);
if ($res->{success}) {
    return {
        comment_id  => $res->{data}{id},
        comment_url => $res->{data}{html_url},
        created_at  => $res->{data}{created_at},
    };
}
die "GitHub API error: " . ($res->{reason} // "HTTP $res->{status}");
PERL_CODE

# ===========================================================================
# Tool 6/12: github_issue_list_comments
# List comments on a GitHub issue.
# GitHub API: GET /repos/{owner}/{repo}/issues/{issue_number}/comments
# ===========================================================================
# Metadata:
#   name: github_issue_list_comments
#   description: List comments on a GitHub issue
#   inputSchema: { owner, repo, issue_number, limit? }
#
our $TOOL_github_issue_list_comments_code = <<'PERL_CODE';
my $owner  = $args->{owner}  or die "Missing required: owner";
my $repo   = $args->{repo}   or die "Missing required: repo";
my $number = $args->{issue_number} or die "Missing required: issue_number";
my $limit  = $args->{limit}  // 30;

my $path = "/repos/$owner/$repo/issues/$number/comments?per_page=$limit&sort=created&direction=desc";
my $res = _github_api("GET", $path);
if ($res->{success}) {
    my @comments;
    for my $c (@{$res->{data} // []}) {
        push @comments, {
            id         => $c->{id},
            body       => $c->{body} // '',
            author     => $c->{user}{login},
            created_at => $c->{created_at},
            updated_at => $c->{updated_at},
        };
    }
    return { comments => \@comments, count => scalar @comments };
}
die "GitHub API error: " . ($res->{reason} // "HTTP $res->{status}");
PERL_CODE

# ===========================================================================
# Tool 7/12: github_get_file
# Get contents of a file from a GitHub repository.
# GitHub API: GET /repos/{owner}/{repo}/contents/{path}
# ===========================================================================
# Metadata:
#   name: github_get_file
#   description: Get file contents from a GitHub repository
#   inputSchema: { owner, repo, path, ref? (branch/commit) }
#
our $TOOL_github_get_file_code = <<'PERL_CODE';
my $owner = $args->{owner} or die "Missing required: owner";
my $repo  = $args->{repo}  or die "Missing required: repo";
my $path  = $args->{path}  or die "Missing required: path";
my $ref   = $args->{ref}   // undef;

my $api_path = "/repos/$owner/$repo/contents/$path";
$api_path .= "?ref=$ref" if $ref;

my $res = _github_api("GET", $api_path);
if ($res->{success}) {
    my $data = $res->{data};
    my $content = '';
    my $size = 0;
    if ($data->{encoding} && $data->{encoding} eq 'base64') {
        use MIME::Base64;
        my $decoded = decode_base64($data->{content});
        utf8::decode($decoded);
        $content = $decoded;
        $size = length($content);
    }
    return {
        name       => $data->{name},
        path       => $data->{path},
        size       => $size,
        sha        => $data->{sha},
        encoding   => $data->{encoding} // '',
        content    => $content,
        download_url => $data->{download_url} // '',
        html_url   => $data->{html_url} // '',
    };
}
die "GitHub API error: " . ($res->{reason} // "HTTP $res->{status}");
PERL_CODE

# ===========================================================================
# Tool 8/12: github_create_or_update_file
# Create or update a file in a GitHub repository.
# GitHub API: PUT /repos/{owner}/{repo}/contents/{path}
# ===========================================================================
# Metadata:
#   name: github_create_or_update_file
#   description: Create or update a file in a GitHub repository
#   inputSchema: { owner, repo, path, content, message?, branch?, sha? (for update) }
#
our $TOOL_github_create_or_update_file_code = <<'PERL_CODE';
use MIME::Base64;
my $owner   = $args->{owner}   or die "Missing required: owner";
my $repo    = $args->{repo}    or die "Missing required: repo";
my $path    = $args->{path}    or die "Missing required: path";
my $content = $args->{content} // '';
my $message = $args->{message} // "Update $path via ai-hub GitHub tools";
my $branch  = $args->{branch}  // undef;
my $sha     = $args->{sha}     // undef;

my $encoded = encode_base64($content, '');
my %payload = (message => $message, content => $encoded);
$payload{branch} = $branch if $branch;
$payload{sha}    = $sha    if $sha;

my $body_str = $main::json_pp_decoder->encode(\%payload);
my $res = _github_api("PUT", "/repos/$owner/$repo/contents/$path", $body_str);
if ($res->{success}) {
    return {
        path        => $res->{data}{content}{path} // $path,
        sha         => $res->{data}{content}{sha} // '',
        commit_sha  => $res->{data}{commit}{sha} // '',
        commit_url  => $res->{data}{commit}{html_url} // '',
    };
}
die "GitHub API error: " . ($res->{reason} // "HTTP $res->{status}");
PERL_CODE

# ===========================================================================
# Tool 9/12: github_search_issues
# Search issues and pull requests on GitHub.
# GitHub API: GET /search/issues?q=...
# ===========================================================================
# Metadata:
#   name: github_search_issues
#   description: Search GitHub issues and pull requests
#   inputSchema: { query, limit?, repo? (optional filter) }
#
our $TOOL_github_search_issues_code = <<'PERL_CODE';
my $query = $args->{query} or die "Missing required: query";
my $limit = $args->{limit} // 10;
my $repo  = $args->{repo}  // undef;

my $q = $query;
$q = "repo:$repo $q" if $repo;
$q =~ s/ /+/g;

my $path = "/search/issues?q=$q&per_page=$limit&sort=created&order=desc";
my $res = _github_api("GET", $path);
if ($res->{success}) {
    my @issues;
    for my $issue (@{$res->{data}{items} // []}) {
        push @issues, {
            number    => $issue->{number},
            title     => $issue->{title},
            state     => $issue->{state},
            repo      => ($issue->{repository_url} =~ m|/repos/(.+)$| ? $1 : ''),
            url       => $issue->{html_url},
            labels    => [map { $_->{name} } @{$issue->{labels} // []}],
            created_at => $issue->{created_at},
            updated_at => $issue->{updated_at},
        };
    }
    return { issues => \@issues, total_count => ($res->{data}{total_count} // 0), count => scalar @issues };
}
die "GitHub API error: " . ($res->{reason} // "HTTP $res->{status}");
PERL_CODE

# ===========================================================================
# Tool 10/12: github_search_code
# Search code across GitHub repositories.
# GitHub API: GET /search/code?q=...
# ===========================================================================
# Metadata:
#   name: github_search_code
#   description: Search code across GitHub repositories
#   inputSchema: { query, limit?, repo? (optional filter), language? (optional filter) }
#
our $TOOL_github_search_code_code = <<'PERL_CODE';
my $query    = $args->{query}    or die "Missing required: query";
my $limit    = $args->{limit}    // 10;
my $repo     = $args->{repo}     // undef;
my $language = $args->{language} // undef;

my $q = $query;
$q = "repo:$repo $q" if $repo;
$q = "$q+language:$language" if $language;
$q =~ s/ /+/g;

my $path = "/search/code?q=$q&per_page=$limit";
my $res = _github_api("GET", $path);
if ($res->{success}) {
    my @results;
    for my $item (@{$res->{data}{items} // []}) {
        push @results, {
            name       => $item->{name},
            path       => $item->{path},
            repo       => ($item->{repository}{full_name} // ''),
            html_url   => $item->{html_url},
            git_url    => $item->{git_url},
        };
    }
    return { results => \@results, total_count => ($res->{data}{total_count} // 0), count => scalar @results };
}
die "GitHub API error: " . ($res->{reason} // "HTTP $res->{status}");
PERL_CODE

# ===========================================================================
# Tool 11/12: github_list_labels
# List labels in a GitHub repository.
# GitHub API: GET /repos/{owner}/{repo}/labels
# ===========================================================================
# Metadata:
#   name: github_list_labels
#   description: List labels in a GitHub repository
#   inputSchema: { owner, repo }
#
our $TOOL_github_list_labels_code = <<'PERL_CODE';
my $owner = $args->{owner} or die "Missing required: owner";
my $repo  = $args->{repo}  or die "Missing required: repo";

my $res = _github_api("GET", "/repos/$owner/$repo/labels?per_page=100");
if ($res->{success}) {
    my @labels;
    for my $label (@{$res->{data} // []}) {
        push @labels, {
            name        => $label->{name},
            color       => $label->{color},
            description => $label->{description} // '',
            default     => $label->{default} // 0,
        };
    }
    return { labels => \@labels, count => scalar @labels };
}
die "GitHub API error: " . ($res->{reason} // "HTTP $res->{status}");
PERL_CODE

# ===========================================================================
# Tool 12/12: github_list_repos
# List repositories for the authenticated user or organization.
# GitHub API: GET /user/repos or GET /orgs/{org}/repos
# ===========================================================================
# Metadata:
#   name: github_list_repos
#   description: List GitHub repositories for a user or organization
#   inputSchema: { type? ("owner","public","private","all"), org?, limit? }
#
our $TOOL_github_list_repos_code = <<'PERL_CODE';
my $type  = $args->{type}  // 'owner';
my $org   = $args->{org}   // undef;
my $limit = $args->{limit} // 30;

my $path;
if ($org) {
    $path = "/orgs/$org/repos?type=$type&per_page=$limit&sort=updated&direction=desc";
} else {
    $path = "/user/repos?type=$type&per_page=$limit&sort=updated&direction=desc";
}

my $res = _github_api("GET", $path);
if ($res->{success}) {
    my @repos;
    for my $repo (@{$res->{data} // []}) {
        push @repos, {
            full_name   => $repo->{full_name},
            description => $repo->{description} // '',
            private     => $repo->{private} // 0,
            html_url    => $repo->{html_url},
            language    => $repo->{language} // '',
            stars       => $repo->{stargazers_count} // 0,
            forks       => $repo->{forks_count} // 0,
            open_issues => $repo->{open_issues_count} // 0,
            updated_at  => $repo->{updated_at},
        };
    }
    return { repositories => \@repos, count => scalar @repos };
}
die "GitHub API error: " . ($res->{reason} // "HTTP $res->{status}");
PERL_CODE

# ===========================================================================
# Generator helper — returns all tool definitions as a list of hashes
# Each entry: { name, description, inputSchema, code }
# ===========================================================================
sub get_all_github_tools {
    return [
        {
            name => 'github_issue_create',
            description => 'Create a new GitHub issue in a repository',
            inputSchema => {
                type => 'object',
                properties => {
                    owner => { type => 'string', description => 'Repository owner (user or org)' },
                    repo  => { type => 'string', description => 'Repository name' },
                    title => { type => 'string', description => 'Issue title' },
                    body  => { type => 'string', description => 'Issue body text (optional)' },
                    labels => { type => 'array', items => { type => 'string' }, description => 'Label names (optional)' },
                    assignees => { type => 'array', items => { type => 'string' }, description => 'Usernames to assign (optional)' },
                },
                required => ['owner', 'repo', 'title'],
            },
            code => $TOOL_github_issue_create_code,
        },
        {
            name => 'github_issue_list',
            description => 'List GitHub issues in a repository with optional filters',
            inputSchema => {
                type => 'object',
                properties => {
                    owner  => { type => 'string', description => 'Repository owner (user or org)' },
                    repo   => { type => 'string', description => 'Repository name' },
                    state  => { type => 'string', description => 'Issue state: open, closed, all (default: open)' },
                    labels => { type => 'string', description => 'Comma-separated label names (optional)' },
                    limit  => { type => 'number', description => 'Max results (default: 30)' },
                },
                required => ['owner', 'repo'],
            },
            code => $TOOL_github_issue_list_code,
        },
        {
            name => 'github_issue_get',
            description => 'Get details of a specific GitHub issue',
            inputSchema => {
                type => 'object',
                properties => {
                    owner        => { type => 'string', description => 'Repository owner (user or org)' },
                    repo         => { type => 'string', description => 'Repository name' },
                    issue_number => { type => 'number', description => 'Issue number' },
                },
                required => ['owner', 'repo', 'issue_number'],
            },
            code => $TOOL_github_issue_get_code,
        },
        {
            name => 'github_issue_update',
            description => 'Update a GitHub issue (title, body, state, labels, assignees)',
            inputSchema => {
                type => 'object',
                properties => {
                    owner        => { type => 'string', description => 'Repository owner (user or org)' },
                    repo         => { type => 'string', description => 'Repository name' },
                    issue_number => { type => 'number', description => 'Issue number' },
                    title        => { type => 'string', description => 'New title (optional)' },
                    body         => { type => 'string', description => 'New body text (optional)' },
                    state        => { type => 'string', description => 'New state: open or closed (optional)' },
                    labels       => { type => 'array', items => { type => 'string' }, description => 'New labels array (optional)' },
                    assignees    => { type => 'array', items => { type => 'string' }, description => 'New assignees array (optional)' },
                },
                required => ['owner', 'repo', 'issue_number'],
            },
            code => $TOOL_github_issue_update_code,
        },
        {
            name => 'github_issue_add_comment',
            description => 'Add a comment to a GitHub issue',
            inputSchema => {
                type => 'object',
                properties => {
                    owner        => { type => 'string', description => 'Repository owner (user or org)' },
                    repo         => { type => 'string', description => 'Repository name' },
                    issue_number => { type => 'number', description => 'Issue number' },
                    body         => { type => 'string', description => 'Comment body text' },
                },
                required => ['owner', 'repo', 'issue_number', 'body'],
            },
            code => $TOOL_github_issue_add_comment_code,
        },
        {
            name => 'github_issue_list_comments',
            description => 'List comments on a GitHub issue',
            inputSchema => {
                type => 'object',
                properties => {
                    owner        => { type => 'string', description => 'Repository owner (user or org)' },
                    repo         => { type => 'string', description => 'Repository name' },
                    issue_number => { type => 'number', description => 'Issue number' },
                    limit        => { type => 'number', description => 'Max results (default: 30)' },
                },
                required => ['owner', 'repo', 'issue_number'],
            },
            code => $TOOL_github_issue_list_comments_code,
        },
        {
            name => 'github_get_file',
            description => 'Get file contents from a GitHub repository',
            inputSchema => {
                type => 'object',
                properties => {
                    owner => { type => 'string', description => 'Repository owner (user or org)' },
                    repo  => { type => 'string', description => 'Repository name' },
                    path  => { type => 'string', description => 'File path in repository' },
                    ref   => { type => 'string', description => 'Branch name or commit SHA (optional, defaults to default branch)' },
                },
                required => ['owner', 'repo', 'path'],
            },
            code => $TOOL_github_get_file_code,
        },
        {
            name => 'github_create_or_update_file',
            description => 'Create or update a file in a GitHub repository',
            inputSchema => {
                type => 'object',
                properties => {
                    owner   => { type => 'string', description => 'Repository owner (user or org)' },
                    repo    => { type => 'string', description => 'Repository name' },
                    path    => { type => 'string', description => 'File path to create/update' },
                    content => { type => 'string', description => 'File content (text)' },
                    message => { type => 'string', description => 'Commit message (optional)' },
                    branch  => { type => 'string', description => 'Branch name (optional, defaults to default branch)' },
                    sha     => { type => 'string', description => 'File SHA (required for update, optional for create)' },
                },
                required => ['owner', 'repo', 'path', 'content'],
            },
            code => $TOOL_github_create_or_update_file_code,
        },
        {
            name => 'github_search_issues',
            description => 'Search GitHub issues and pull requests',
            inputSchema => {
                type => 'object',
                properties => {
                    query => { type => 'string', description => 'Search query (GitHub search syntax)' },
                    limit => { type => 'number', description => 'Max results (default: 10)' },
                    repo  => { type => 'string', description => 'Optional: limit search to repo (owner/name)' },
                },
                required => ['query'],
            },
            code => $TOOL_github_search_issues_code,
        },
        {
            name => 'github_search_code',
            description => 'Search code across GitHub repositories',
            inputSchema => {
                type => 'object',
                properties => {
                    query    => { type => 'string', description => 'Search query (GitHub search syntax)' },
                    limit    => { type => 'number', description => 'Max results (default: 10)' },
                    repo     => { type => 'string', description => 'Optional: limit search to repo (owner/name)' },
                    language => { type => 'string', description => 'Optional: filter by language (e.g. Perl, Go, Python)' },
                },
                required => ['query'],
            },
            code => $TOOL_github_search_code_code,
        },
        {
            name => 'github_list_labels',
            description => 'List labels in a GitHub repository',
            inputSchema => {
                type => 'object',
                properties => {
                    owner => { type => 'string', description => 'Repository owner (user or org)' },
                    repo  => { type => 'string', description => 'Repository name' },
                },
                required => ['owner', 'repo'],
            },
            code => $TOOL_github_list_labels_code,
        },
        {
            name => 'github_list_repos',
            description => 'List GitHub repositories for a user or organization',
            inputSchema => {
                type => 'object',
                properties => {
                    type  => { type => 'string', description => 'Type: owner, public, private, all (default: owner)' },
                    org   => { type => 'string', description => 'Organization name (optional, omit for user repos)' },
                    limit => { type => 'number', description => 'Max results (default: 30)' },
                },
                required => [],
            },
            code => $TOOL_github_list_repos_code,
        },
    ];
}

1; # End of GitHub tools package