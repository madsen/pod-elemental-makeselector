#---------------------------------------------------------------------
package Pod::Elemental::MakeSelector;
#
# Copyright 2012 Christopher J. Madsen
#
# Author: Christopher J. Madsen <perl@cjmweb.net>
# Created: 5 Jun 2012
#
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See either the
# GNU General Public License or the Artistic License for more details.
#
# ABSTRACT: Build complex selectors as a single sub
#---------------------------------------------------------------------

use 5.010_001;                  # smart-matching is broken in 5.10.0
use strict;
use warnings;

our $VERSION = '0.04';
# This file is part of {{$dist}} {{$dist_version}} ({{$date}})

use Carp qw(croak);

use Sub::Exporter -setup => {
  exports => [ qw(make_selector) ],
  groups  => { default => [ qw(make_selector) ]},
};

# In Perl 5.18, smartmatch emits a warning
no if $] >= 5.018, warnings => "experimental::smartmatch";

#=====================================================================
sub add_value
{
  my ($valuesR, $value) = @_;

  push @$valuesR, $value;

  '$val' . $#$valuesR;
} # end add_value

#---------------------------------------------------------------------
sub join_expressions
{
  my ($op, $expressionsR) = @_;

  return @$expressionsR unless @$expressionsR > 1;

  '(' . join("\n    $op ", @$expressionsR) . "\n  )";
} # end join_expressions

#---------------------------------------------------------------------
sub conjunction_action
{
  my ($op, $valuesR, $inputR) = @_;

  my $arrayR = shift @$inputR;
  croak "Expected arrayref for -$op, got $arrayR"
      unless ref($arrayR) eq 'ARRAY';

  my @expressions;
  build_selector($valuesR, \@expressions, @$arrayR);

  join_expressions($op, \@expressions);
} # end conjunction_action

#---------------------------------------------------------------------
sub region_action
{
  my ($valuesR, $inputR, $pod) = @_;

  my @expressions = type_action(qw(isa Element::Pod5::Region));

  push @expressions, ($pod ? '' : 'not ') . '$para->is_pod'
      if defined $pod;

  if (@$inputR and not $inputR->[0] =~ /^-/) {
    my $name = add_value($valuesR, shift @$inputR);
    push @expressions, "\$para->format_name ~~ $name";
  } # end if specific format(s) listed

  join_expressions(and => \@expressions);
} # end region_action

#---------------------------------------------------------------------
sub type_action
{
  my ($check, $class) = @_;

  "\$para->$check('Pod::Elemental::$class')";
} # end type_action

#---------------------------------------------------------------------
our %action = (
  -and     => sub { conjunction_action(and => @_) },
  -or      => sub { conjunction_action(or  => @_) },
  -blank   => sub { type_action(qw(isa Element::Generic::Blank)) },
  -flat    => sub { type_action(qw(does Flat)) },
  -node    => sub { type_action(qw(does Node)) },

  -code => sub {
    my ($valuesR, $inputR) = @_;

    my $name = add_value($valuesR,
                          shift @$inputR // croak "-code requires a value");
    "$name->(\$para)";
  }, #end -code

  -command => sub {
    my ($valuesR, $inputR) = @_;

    my @expressions = type_action(qw(does Command));

    if (@$inputR and not $inputR->[0] =~ /^-/) {
      my $name = add_value($valuesR, shift @$inputR);
      push @expressions, "\$para->command ~~ $name";
    } # end if specific command(s) listed

    join_expressions(and => \@expressions);
  }, #end -command

  -content => sub {
    my ($valuesR, $inputR) = @_;

    my $name = add_value($valuesR,
                          shift @$inputR // croak "-content requires a value");
    "\$para->content ~~ $name";
  }, #end -content

  -region       => \&region_action,
  -podregion    => sub { region_action(@_, 1) },
  -nonpodregion => sub { region_action(@_, 0) },
); # end %action

=head1 CRITERIA

Most criteria that accept a parameter test it using smart matching,
which means that they accept a string, a regex, or an arrayref of
strings and/or regexes.  (This also means that Perl 5.10.1 is required
to use Pod::Elemental::MakeSelector.)

Optional parameters must not begin with C<->, or they will be treated
as criteria instead.

=head2 Simple Criteria

  -blank, # isa Pod::Elemental::Element::Generic::Blank
  -flat,  # does Pod::Elemental::Flat
  -node,  # does Pod::Elemental::Node

=head2 Command Paragraphs

  -command,           # does Pod::Elemental::Command
  -command => 'head1',           # and is =head1
  -command => qr/^head[23]/,     # and matches regex
  -command => [qw(head1 head2)], # 1 element must match

=head2 Content

  -content => 'AUTHOR',       # matches =head1 AUTHOR
  -content => qr/^AUTHORS?$/, # or =head1 AUTHORS
  -content => [qw(AUTHOR BUGS)], # 1 element must match

This criterion is normally used in conjunction with C<-command> to
select a section with a specific title.

=head2 Regions

  -region, # isa Pod::Elemental::Element::Pod5::Region
  -region => 'list',      # and format_name eq 'list'
  -region => qr/^list$/i, # and format_name matches regex
  -region => [qw(list group)], # 1 element must match
  -podregion    => 'list',          # =for :list
  -nonpodregion => 'Pod::Coverage', # =for Pod::Coverage

Regions are created with the C<=begin> or C<=for> commands.  The
C<-podregion> and C<-nonpodregion> criteria work exactly like
C<-region>, but they ensure that C<is_pod> is either true or false,
respectively.

=head2 Conjunctions

  -and => [ ... ], # all criteria must be true
  -or  => [ ... ], # at least one must be true

These take an arrayref of criteria, and combine them using the
specified operator.  Note that C<make_selector> does C<-and> by default;
S<C<make_selector @criteria>> is equivalent to
S<C<< make_selector -and => \@criteria >>>.

=head2 Custom Criteria

  -code => sub { ... }, # test $_[0] any way you want
  -code => $selector,   # also accepts another selector

=cut

#---------------------------------------------------------------------
sub build_selector
{
  my $valuesR = shift;
  my $expR    = shift;

  while (@_) {
    my $type = shift;

    my $action = $action{$type}
        or croak "Expected selector type, got $type";

    push @$expR, $action->($valuesR, \@_);
  } # end while more selectors
} # end build_selector
#---------------------------------------------------------------------

# FIXME: These subs will be documented when I figure out how
# make_selector should be extended.

=for Pod::Coverage
add_value
build_selector
conjunction_action
join_expressions
region_action
type_action


=sub make_selector

  $selector = make_selector( ... );

C<make_selector> takes a list of criteria and returns a selector that
tests whether a supplied paragraph matches all the criteria.  It does
not allow you to pass a paragraph to be checked immediately; if you
want to do that, then call the selector yourself.  i.e., these two
lines are equivalent:

  s_command(head1 => $para); # From Pod::Elemental::Selectors
  make_selector(qw(-command head1))->($para);

=cut

sub make_selector
{
  my @values;
  my @expressions;

  build_selector(\@values, \@expressions, @_);

  my $code = ("sub { my \$para = shift; return (\n  " .
              join("\n  and ", @expressions) .
              "\n)}\n");

  $code = sprintf("my (%s) = \@values;\n\n%s",
                  join(', ', map { '$val' . $_ } 0 .. $#values),
                  $code)
      if @values;

  #say $code;
  my ($sub, $err);
  {
    local $@;
    $sub = eval $code;
    $err = $@;
  }

  unless (ref $sub) {
    my $lineNum = ($code =~ tr/\n//);
    my $fmt = '%' . length($lineNum) . 'd: ';
    $lineNum = 0;
    $code =~ s/^/sprintf $fmt, ++$lineNum/gem;

    die "Building selector failed:\n$code$err";
  }

  $sub;
} # end make_selector

#=====================================================================
# Package Return Value:

1;

=head1 SYNOPSIS

  use Pod::Elemental::MakeSelector;

  my $author_selector = make_selector(
    -command => 'head1',
    -content => qr/^AUTHORS?$/,
  );

=head1 DESCRIPTION

The selectors provided by L<Pod::Elemental::Selectors> are fairly
limited, and there's no built-in way to combine them.  For example,
there's no simple way to generate a selector that matches a section
with a specific name (a fairly common requirement).

This module exports a single subroutine: C<make_selector>.  It can
handle everything that Pod::Elemental::Selectors can do, plus many
things it can't.  It also makes it easy to combine criteria.  It
compiles all the criteria you supply into a single coderef.

A selector is just a coderef that expects a single parameter: an
object that does Pod::Elemental::Paragraph.  It returns a true value
if the paragraph meets the selector's criteria.

=head1 SEE ALSO

L<Pod::Elemental::Selectors> comes with L<Pod::Elemental>, but is much
more limited than this module.

=head1 DEPENDENCIES

Pod::Elemental::MakeSelector requires L<Pod::Elemental> and Perl 5.10.1
or later.
