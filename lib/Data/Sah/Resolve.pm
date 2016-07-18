package Data::Sah::Resolve;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(resolve_schema);

sub _resolve {
    my ($opts, $type, $clsets) = @_;

    (my $typemod_pm = "Data/Sah/Type/$type.pm") =~ s!::!/!g;
    eval { require $typemod_pm; 1 };
    # already a builtin-type, so just return the schema's type name & clause set
    return [$type, $clsets] unless $@;

    # not a type, try a schema under Sah::Schema
    my $schmod = "Sah::Schema::$type";
    (my $schmod_pm = "$schmod.pm") =~ s!::!/!g;
    eval { require $schmod_pm; 1 };
    die "Not a known type/schema name '$type'" if $@;
    no strict 'refs';
    my $sch2 = ${"$schmod\::schema"};
    die "BUG: Schema module $schmod doesn't contain \$schema" unless $sch2;
    push @$clsets, $sch2->[1];
    _resolve($opts, $sch2->[0], $clsets);
}

sub resolve_sah_schema {
    my $opts = ref($_[0]) eq 'HASH' ? shift : {};
    my $sch = shift;

    unless ($opts->{schema_is_normalized}) {
        require Data::Sah::Normalize;
        $sch =  Data::Sah::Normalize::normalize_schema($sch);
    }

    _resolve($opts, $sch->[0], [$sch->[1]]);
}

1;
# ABSTRACT: Resolve Sah schema

=head1 SYNOPSIS

 use Data::Sah::Resolve qw(resolve_schema);

 my $sch = resolve_schema("int");
 # => ["int", {}, {}]

 my $sch = resolve_schema("posint*");
 # => ["int", {req=>1, min=>0}, {}]

 my $sch = resolve_schema([posint => div_by => 3]);
 # => ["int", {min=>0, div_by=>3}, {}]

 my $sch = resolve_schema([array => of=>"posint*"]);
 # => ["array", {of=>["int", {req=>1, min=>0}, {}]}, {}]


=head1 DESCRIPTION


=head1 FUNCTIONS

=head2 resolve_schema([ \%opts, ] $sch) => sch

Extract all subschemas found inside Sah schema C<$sch>. Schema will be
normalized first, then schemas from all clauses which contains subschemas will
be collected recursively.

Known options:

=over

=item * schema_is_normalized => bool (default: 0)

When set to true, function will skip normalizing schema and assume input schema
is normalized.

=back


=head1 SEE ALSO

L<Sah>, L<Data::Sah>

=cut
