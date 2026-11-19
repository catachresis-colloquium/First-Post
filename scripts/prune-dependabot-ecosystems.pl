#!/usr/bin/env perl
# SPDX-License-Identifier: MPL-2.0
# Prune Dependabot entries using the operator's archetype, not file presence:
# newly minted repositories have no manifests yet. Never retain the invalid
# `nix` ecosystem, which causes GitHub to reject the entire configuration.
# Usage: prune-dependabot-ecosystems.pl <file> <keep...>
use strict;
use warnings;
use autodie;

@ARGV >= 2 or die "Usage: $0 <file> <keep...>\n";
my $path = shift @ARGV;
my %keep = map { $_ => 1 } grep { $_ ne 'nix' } @ARGV;
if (!-f $path) {
    print "  dependabot: $path absent, nothing to prune\n";
    exit 0;
}
open my $input, '<:encoding(UTF-8)', $path;
my $text = do { local $/; <$input> };
close $input;
my @parts = split /(?=^[ \t]*-[ \t]*package-ecosystem:)/m, $text;
my $head = @parts && $parts[0] !~ /^[ \t]*-[ \t]*package-ecosystem:/ ? shift @parts : '';
if (!@parts) {
    print "  dependabot: no ecosystem entries found\n";
    exit 0;
}
my (@kept, @dropped);
for my $entry (@parts) {
    my ($name) = $entry =~ /package-ecosystem:[ \t]*["']?([A-Za-z-]+)/;
    $name //= '?';
    push @{ $keep{$name} ? \@kept : \@dropped }, [$name, $entry];
}
if (!@kept) {
    # An empty updates list is invalid too; preserve the original config.
    print "  dependabot: refusing to prune every entry; left unchanged\n";
} elsif (!@dropped) {
    print "  dependabot: nothing to prune\n";
} else {
    open my $output, '>:encoding(UTF-8)', $path;
    print {$output} $head, map { $_->[1] } @kept;
    close $output;
    print '  dependabot: kept ', join(', ', map { $_->[0] } @kept),
          ' / dropped ', join(', ', map { $_->[0] } @dropped), "\n";
}
