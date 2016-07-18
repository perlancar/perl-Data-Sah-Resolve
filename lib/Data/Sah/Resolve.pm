package Data::Sah::Resolve;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(resolve_sah_schema);

sub resolve_sah_schema {
use Data::Sah::Normalize qw(normalize_schema);

}

1;
# ABSTRACT: Resolve Sah schema

=head1 SYNOPSIS

 use Data::Sah::Resolve qw(resolve_sah_schema);

 my $sch = resolve_sah_schema("int");
 # => ["int", {}, {}]

 my $sch = resolve_sah_schema("posint*");
 # => ["int", {req=>1, min=>0}, {}]

 my $sch = resolve_sah_schema([posint => div_by => 3]);
 # => ["int", {min=>0, div_by=>3}, {}]

 my $sch = resolve_sah_schema([array => of=>"posint*"]);
 # => ["array", {of=>["int", {req=>1, min=>0}, {}]}, {}]


=head1 DESCRIPTION


=head1 FUNCTIONS

=head2 resolve_sah_schema([ \%opts, ] $sch) => sch

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
