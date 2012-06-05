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

use 5.010;
use strict;
use warnings;

our $VERSION = '0.01';
# This file is part of {{$dist}} {{$dist_version}} ({{$date}})

use Carp qw(croak);

use Sub::Exporter -setup => {
  exports => [ qw(make_selector) ],
  groups  => { default => [ qw(make_selector) ]},
};

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
} #end region_action

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
  -bad     => sub { 'foobar' },

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

__END__

=head1 SYNOPSIS

  use Pod::Elemental::MakeSelector;
