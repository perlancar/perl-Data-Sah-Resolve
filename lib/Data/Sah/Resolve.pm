package Data::Sah::Resolve;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(resolve_schema);

sub _resolve {
    my ($opts, $type, $clsets, $seen) = @_;

    die "Recursive schema definition: ".join(" -> ", @$seen, $type)
        if grep { $type eq $_ } @$seen;
    push @$seen, $type;

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
    unshift @$clsets, $sch2->[1];
    _resolve($opts, $sch2->[0], $clsets, $seen);
}

sub resolve_schema {
    my $opts = ref($_[0]) eq 'HASH' ? shift : {};
    my $sch = shift;

    unless ($opts->{schema_is_normalized}) {
        require Data::Sah::Normalize;
        $sch =  Data::Sah::Normalize::normalize_schema($sch);
    }
    $opts->{merge_clause_sets} //= 1;

    my $res = _resolve($opts, $sch->[0], keys(%{$sch->[1]}) ? [$sch->[1]] : [], []);

  MERGE:
    {
        last unless $opts->{merge_clause_sets};
        last if @{ $res->[1] } < 2;

        my @clsets = (shift @{ $res->[1] });
        for my $clset (@{ $res->[1] }) {
            my $has_merge_mode_keys;
            for (keys %$clset) {
                if (/\Amerge\./) {
                    $has_merge_mode_keys = 1;
                    last;
                }
            }
            if ($has_merge_mode_keys) {
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

=item * merge_clause_sets => bool (default: 1)

=back


=head1 SEE ALSO

L<Sah>, L<Data::Sah>

=cut
