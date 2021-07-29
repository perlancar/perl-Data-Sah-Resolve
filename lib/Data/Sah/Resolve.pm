package Data::Sah::Resolve;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(resolve_schema);

sub _clset_has_merge {
    my $clset = shift;
    for (keys %$clset) {
        return 1 if /\Amerge\./;
    }
    0;
}

sub _resolve {
    my ($opts, $type, $res) = @_;

    die "Cannot resolve Sah schema: circular schema definition: ".
        join(" -> ", @{$res->[2]{intermediates}}, $type)
        if grep { $type eq $_ } @{$res->[2]{intermediates}};

    unshift @{$res->[2]{intermediates}}           , $type;
    unshift @{$res->[2]{intermediates_have_merge}}, undef; # temporary value

    # check whether $type is a built-in Sah type
    (my $typemod_pm = "Data/Sah/Type/$type.pm") =~ s!::!/!g;
    eval { require $typemod_pm; 1 };
    my $err = $@;
    unless ($err) {
        # already a builtin-type, so we stop here
        return;
    }
    die "Cannot resolve Sah schema: can't check whether $type is a builtin Sah type: $err"
        unless $err =~ /\ACan't locate/;

    # not a type, try a schema under Sah::Schema
    my $schmod = "Sah::Schema::$type";
    (my $schmod_pm = "$schmod.pm") =~ s!::!/!g;
    eval { require $schmod_pm; 1 };
    die "Cannot resolve Sah schema: not a known built-in Sah type '$type' (can't locate ".
        "Data::Sah::Type::$type) and not a known schema name '$type' ($@)"
            if $@;
    no strict 'refs';
    my $sch2 = ${"$schmod\::schema"};
    die "Cannot resolve Sah schema: BUG: Schema module $schmod doesn't contain \$schema"
        unless $sch2;
    $res->[0] = $sch2->[0];
    unshift @{ $res->[1] }, $sch2->[1];
    $res->[2]{intermediates_have_merge}[0] = _clset_has_merge($sch2->[1]);
    _resolve($opts, $sch2->[0], $res);
}

sub resolve_schema {
    my $opts = ref($_[0]) eq 'HASH' ? shift : {};
    my $sch = shift;

    unless ($opts->{schema_is_normalized}) {
        require Data::Sah::Normalize;
        $sch =  Data::Sah::Normalize::normalize_schema($sch);
    }
    $opts->{merge_clause_sets} //= 1;

    my $res = [$sch->[0], keys(%{$sch->[1]}) ? [$sch->[1]] : [], {
        intermediates            => [],
        intermediates_have_merge => [],
        clset_has_merge          => _clset_has_merge($sch->[1]),
    }];
    _resolve($opts, $sch->[0], $res);

  MERGE:
    {
        last unless $opts->{merge_clause_sets};
        last if @{ $res->[1] } < 2;

        my @clsets = (shift @{ $res->[1] });
        for my $clset (@{ $res->[1] }) {
            if (_clset_has_merge($clset)) {
                state $merger = do {
                    require Data::ModeMerge;
                    my $mm = Data::ModeMerge->new(config => {
                        recurse_array => 1,
                    });
                    $mm->modes->{NORMAL}  ->prefix   ('merge.normal.');
                    $mm->modes->{NORMAL}  ->prefix_re(qr/\Amerge\.normal\./);
                    $mm->modes->{ADD}     ->prefix   ('merge.add.');
                    $mm->modes->{ADD}     ->prefix_re(qr/\Amerge\.add\./);
                    $mm->modes->{CONCAT}  ->prefix   ('merge.concat.');
                    $mm->modes->{CONCAT}  ->prefix_re(qr/\Amerge\.concat\./);
                    $mm->modes->{SUBTRACT}->prefix   ('merge.subtract.');
                    $mm->modes->{SUBTRACT}->prefix_re(qr/\Amerge\.subtract\./);
                    $mm->modes->{DELETE}  ->prefix   ('merge.delete.');
                    $mm->modes->{DELETE}  ->prefix_re(qr/\Amerge\.delete\./);
                    $mm->modes->{KEEP}    ->prefix   ('merge.keep.');
                    $mm->modes->{KEEP}    ->prefix_re(qr/\Amerge\.keep\./);
                    $mm;
                };
                my $merge_res = $merger->merge($clsets[-1], $clset);
                unless ($merge_res->{success}) {
                    die "Can't merge clause set: $merge_res->{error}";
                }
                $clsets[-1] = $merge_res->{result};
            } else {
                push @clsets, $clset;
            }
        }

        $res->[1] = \@clsets;
    }

    $res;
}

1;
# ABSTRACT: Resolve Sah schema

=head1 SYNOPSIS

 use Data::Sah::Resolve qw(resolve_schema);

 my $sch = resolve_schema("int");
 # => ["int", []]

 my $sch = resolve_schema("posint*");
 # => ["int", [{min=>1}, {req=>1}]

 my $sch = resolve_schema([posint => div_by => 3]);
 # => ["int", {min=>1}, {div_by=>3}]

 my $sch = resolve_schema(["posint", "merge.delete.min"=>undef, div_by => 3]);
 # => ["int", {div_by=>3}]


=head1 DESCRIPTION


=head1 FUNCTIONS

=head2 resolve_schema([ \%opts, ] $sch) => sch

Sah schemas can be defined in terms of other schemas. The resolving process
follows the base schema recursively until it finds a builtin type as the base.

This routine performs the following steps:

=over

=item 1. Normalize the schema

Unless C<schema_is_normalized> option is true, in which case schema is assumed
to be normalized already.

=item 2. Check if the schema's type is a builtin type

Currently this is done by checking if the module of the name C<<
Data::Sah::Type::<type> >> is loadable. If it is a builtin type then we are
done.

=item 3. Check if the schema's type is the name of another schema

This is done by checking if C<< Sah::Schema::<name> >> module exists and is
loadable. If this is the case then we retrieve the base schema from the
C<$schema> variable in the C<< Sah::Schema::<name> >> package and repeat the
process while accumulating and/or merging the clause sets.

=item 4. If schema's type is neither, we die.

=back

Returns C<< [$base_type, \@clause_sets, \%additional] >>.

Example 1: C<int>.

First we normalize to C<< ["int",{}] >>. The type is C<int> and it is a builtin
type (L<Data::Sah::Type::int> exists) so the final result is C<< ["int", []] >>.

Example 2: C<posint*>.

First we normalize to C<< ["posint",{req=>1}] >>. The type is C<posint> and it
is the name of another schema (L<Sah::Schema::posint>). We retrieve the
C<posint> schema which is C<< ["int", {summary=>"Positive integer (1,2,3,...)",
min=>1}] >>. We now try to resolve C<int> and find that it's a builtin type. So
the final result is: C<< ["int", [ {req=>1}, {summary=>"Positive integer
(1,2,3,...)", min=>1} ], {}] >>.

Known options:

=over

=item * schema_is_normalized => bool (default: 0)

When set to true, function will skip normalizing schema and assume input schema
is normalized.

=item * merge_clause_sets => bool (default: 1)

Whether to merge clause sets when a clause set contains merge keys. This is
normally set to true as this is the proper behavior specified by the L<Sah>
specification. However, for some purposes we might not need merging and can skip
this step to save some time.

=back

Additional data returned (in the third element's hash keys):

=over

=item * intermediates

Array. This is a list of intermediate schema names, from the deepest to the
shallowest. The first element of this arrayref is the builtin Sah type and the
last element is the original unresolved schema's type.

See also: L</intermediates_have_merge>

=item * clset_has_merge

Bool. Tells whether the clause set of the being-resolved schema contains merge
prefixes.

=item * intermediates_have_merge

Array. This is a list to accompany the L</intermediates> key. Each element of
this list tells whether any of clause set of the schema in the corresponding
element in C<intermediates> contains merge prefixes. The builtin type will have
C<undef> value. For example, suppose schema C<sch1> is:

 ["sch2", {"merge.normal.min_len"=>10}]

and schema C<sch2> is:

 ["sch3", {min_len=>5, match=>qr/foo/, max_len=>32}]

and schema C<sch3> is:

 ["str"]

then resolving C<< ["sch1", {match=>qr/bar/}] >> will result in this:

 ["str",
  [
    {},
    {min_len=>10, match=>qr/foo/, max_len=>32},
  ],
  {
    intermediates            => ["str", "sch3", "sch2", "sch1"],
    intermediates_have_merge => [undef, 0     , 0     , 1     ],
    clset_has_merge          => 1,
  }]

=back


=head1 SEE ALSO

L<Sah>, L<Data::Sah>

=cut
