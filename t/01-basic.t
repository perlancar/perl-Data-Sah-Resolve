#!perl

use 5.010001;
use strict;
use warnings;
use Test::Deep;
use Test::Exception;
use Test::More 0.98;
use Test::Needs;

use Data::Dmp;
use Data::Sah::Resolve qw(resolve_schema);

subtest "unknown" => sub {
    test_resolve(
        name   => "unknown -> dies",
        schema => "foo",
        dies => 1,
    );
};

subtest "tests that need Sah-Schemas-Examples distribution" => sub {
    test_needs "Sah::Schemas::Examples"; # for Sah::Schema::example::recurse1 et al
    subtest "recursion" => sub {
        test_resolve(
            schema => "example::recurse1",
            dies => 1,
        );
        test_resolve(
            schema => "example::recurse2a",
            dies => 1,
        );
        test_resolve(
            schema => "example::recurse2b",
            dies => 1,
        );
    };
};

subtest "tests that need Data-Sah distribution" => sub {
    test_needs "Data::Sah"; # for Data::Sah::Type::int

    test_resolve(
        schema => "int",
        result => ["int", [], {intermediates=>["int"]}],
    );
    test_resolve(
        schema => ["int"],
        result => ["int", [], {intermediates=>["int"]}],
    );
    test_resolve(
        schema => ["int", {}],
        result => ["int", [], {intermediates=>["int"]}],
    );
    test_resolve(
        schema => ["int", min=>2],
        result => ["int", [{min=>2}], {intermediates=>["int"]}],
    );

    subtest "tests that need Sah-Schemas-Int" => sub {
        test_needs "Sah::Schemas::Int"; # provides Sah::Schema::posint, et al

        test_resolve(
            schema => "posint",
            result => ["int", [superhashof({min=>1})], {intermediates=>["posint", "int"]}],
        );
        test_resolve(
            schema => ["posint", min=>10],
            result => ["int", [superhashof({min=>1}), {min=>10}], {intermediates=>["posint","int"]}],
        );
        test_resolve(
            schema => ["posint", "merge.delete.min"=>undef],
            result => ["int", [superhashof({})], {intermediates=>["posint","int"]}],
        );

        test_resolve(
            schema => ["poseven"],
            result => ["int", [superhashof({ min=>1}), superhashof({div_by=>2})], {intermediates=>["poseven","posint","int"]}],
        );
        test_resolve(
            schema => ["poseven", min=>10, div_by=>3],
            result => ["int", [superhashof({min=>1}), superhashof({div_by=>2}), superhashof({min=>10, div_by=>3})], {intermediates=>["poseven","posint","int"]}],
        );

        subtest "tests that need Sah-Schemas-Examples" => sub {
            test_needs "Sah::Schemas::Examples"; # provides Sah::Schema::example::has_merge et al
            test_resolve(
                name   => "2 merges",
                schema => ["example::has_merge", {"merge.normal.div_by"=>3}],
                result => ["int", [superhashof({div_by=>3})], {intermediates=>["example::has_merge","posint","int"]}],
            );
        };
    };
};

# XXX test error in merging -> dies

DONE_TESTING:
done_testing;

sub test_resolve {
    my %args = @_;

    subtest(($args{name} // dmp($args{schema})), sub {
        my $res;
        my $opts = $args{opts} // {};
        if ($args{dies}) {
            dies_ok { resolve_schema($opts, $args{schema}) } "resolve dies"
                or return;
        } else {
            lives_ok { $res = resolve_schema($opts, $args{schema}) } "resolve lives"
                or return;
        }
        if ($args{result}) {
            cmp_deeply($res, $args{result}, "result")
                or diag explain $res;
        }
    });
}
