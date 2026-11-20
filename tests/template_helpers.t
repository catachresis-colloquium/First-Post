#!/usr/bin/env perl
# SPDX-License-Identifier: MPL-2.0
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use Cwd qw(abs_path);

my $repo = abs_path('.');
my $tmp = tempdir(CLEANUP => 1);
sub write_file {
    my ($path, $text) = @_;
    open my $f, '>:raw', $path or die $!;
    print {$f} $text;
    close $f or die $!;
}
sub read_file {
    open my $f, '<:raw', $_[0] or die $!;
    local $/;
    return <$f>;
}
sub run_helper {
    my ($script, @args) = @_;
    is(system($^X, "$repo/scripts/$script.pl", @args), 0, "$script exits successfully");
}

my $config = "$tmp/dependabot.yml";
my $header = "# Header\nversion: 2\nupdates:\n";
my $actions = "  - package-ecosystem: \"github-actions\"\n    directory: /\n    # action schedule\n    schedule:\n      interval: weekly\n";
my $cargo = "  - package-ecosystem: 'cargo'\n    directory: /\n";
my $nix = "  - package-ecosystem: nix\n    directory: /\n";
write_file($config, $header . $actions . $nix . $cargo);
run_helper('prune-dependabot-ecosystems', $config, 'github-actions', 'cargo', 'nix');
is(read_file($config), $header . $actions . $cargo, 'keeps requested valid entries and header, drops nix even when requested');
run_helper('prune-dependabot-ecosystems', $config, 'github-actions');
is(read_file($config), $header . $actions, 'prunes unused entries');
run_helper('prune-dependabot-ecosystems', $config, 'github-actions');
is(read_file($config), $header . $actions, 'pruning is idempotent');
run_helper('prune-dependabot-ecosystems', $config, 'cargo');
is(read_file($config), $header . $actions, 'refuses empty updates list');
write_file($config, $actions . $cargo);
run_helper('prune-dependabot-ecosystems', $config, 'cargo');
is(read_file($config), $cargo, 'handles an entry at the start of the file');
write_file($config, $header);
run_helper('prune-dependabot-ecosystems', $config, 'cargo');
is(read_file($config), $header, 'leaves entry-free files unchanged');
run_helper('prune-dependabot-ecosystems', "$tmp/missing.yml", 'cargo');
ok(!-e "$tmp/missing.yml", 'does not create missing configs');

my $root = "$tmp/tree";
make_path($root, map { "$root/$_" } qw(.git node_modules .venv target dist nested));
my $marker = "TEMPLATE " . "INSTRUCTIONS";
my $block = "<!-- $marker\nremove me\n-->\n";
my $prefix = "<!--\nSPDX-License-Identifier: MPL-2.0\n-->\n# Heading\n\n";
my $suffix = "Prose mentions $marker.\n<!-- ordinary comment -->\n";
write_file("$root/nested/policy.md", $prefix . $block . $suffix . $block);
write_file("$root/prose.md", $prefix . $suffix);
write_file("$root/binary", "\xff" . $block);
for my $dir (qw(.git node_modules .venv target dist)) {
    write_file("$root/$dir/keep.md", $block);
}
write_file("$tmp/external.md", $block);
symlink "$tmp/external.md", "$root/link.md" or die $!;
run_helper('strip-instruction-blocks', $root);
is(read_file("$root/nested/policy.md"), $prefix . $suffix, 'removes multiple instruction comments, preserves SPDX, heading and prose');
is(read_file("$root/prose.md"), $prefix . $suffix, 'marker mentioned in prose is preserved');
is(read_file("$root/binary"), "\xff" . $block, 'non-UTF-8 file is untouched');
is(read_file("$tmp/external.md"), $block, 'symlink target is untouched');
for my $dir (qw(.git node_modules .venv target dist)) {
    is(read_file("$root/$dir/keep.md"), $block, "skips $dir");
}
run_helper('strip-instruction-blocks', $root);
is(read_file("$root/nested/policy.md"), $prefix . $suffix, 'stripping is idempotent');
done_testing();
