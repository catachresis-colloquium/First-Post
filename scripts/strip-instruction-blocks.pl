#!/usr/bin/env perl
# SPDX-License-Identifier: MPL-2.0
# Delete template instruction comments AFTER token substitution. Match within
# a single HTML comment so that earlier SPDX headers and headings survive.
# Usage: strip-instruction-blocks.pl [root] (default "."). Idempotent.
use strict;
use warnings;
use Encode qw(decode encode FB_CROAK);
use File::Find qw(find);

my $root = $ARGV[0] // '.';
my %skip = map { $_ => 1 } qw(.git node_modules .venv target dist);
my @paths;
find({ no_chdir => 1, wanted => sub {
    if (-d $_ && grep { $skip{$_} } split m{/}, $File::Find::name) {
        $File::Find::prune = 1;
        return;
    }
    push @paths, $File::Find::name if -f $_ && !-l $_;
}}, $root);
my $changed = 0;
for my $path (sort @paths) {
    open my $input, '<:raw', $path or next;
    my $bytes = do { local $/; <$input> };
    close $input;
    my $text = eval { decode('UTF-8', $bytes, FB_CROAK) };
    next if $@ || !defined $text;
    # Mirror universal newline reading in the original helper.
    $text =~ s/\r\n?/\n/g;
    my $new = $text;
    $new =~ s/<!--(?:(?!-->).)*?TEMPLATE INSTRUCTIONS(?:(?!-->).)*?-->[ \t]*\n?//sg;
    next if $new eq $text;
    $new =~ s/\n{3,}/\n\n/g;
    open my $output, '>:raw', $path or die "Cannot write $path: $!\n";
    print {$output} encode('UTF-8', $new) or die "Cannot write $path: $!\n";
    close $output or die "Cannot close $path: $!\n";
    print "  instruction block: stripped from $path\n";
    ++$changed;
}
print $changed ? "  instruction blocks: $changed file(s) cleaned\n"
               : "  instruction blocks: none found\n";
