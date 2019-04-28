#!/usr/bin/env perl

use strict;

use FindBin '$Bin';
use lib $Bin;

use Test::More;
use Test::Deep;
use TypeComparator;

use JSON;
use JSON::Schema::Fit;

*_n = \&TypeComparator::real_number;
*_f = \&TypeComparator::real_float_number;
*_s = \&TypeComparator::real_string;

my $schema = {
    type => 'object',
    additionalProperties => 0,
    properties => {
        aa => { type => 'boolean' },
        bb => { type => 'integer', multipleOf => 5, maximum => 10 },
        cc => { type => 'number', multipleOf => 0.01 },
        dd => { type => 'string' },
        ee => { type => 'integer', default => 42 },
        ff => { type => 'string', enum => [qw.foo bar zbr ugh.], default => 'foo' },
        gg => { type => 'string', enum => [qw.0 1 info debug.],  default => 'info' },
    },
};

my $raw_data = {
    aa => 1,
    bb => "22",
    cc => "33.333333",
    dd => 77,
    ff => 'food',
    gg => 0,
    _debug => "stacktrace",
};

my @default_opts = qw/booleans numbers round_numbers strings hash_keys/;
my @optional_opts = qw/clamp_numbers fill_defaults replace_invalid_enum/;

my @tests = (
    [ default => JSON::Schema::Fit->new(),
        {aa => JSON::true, bb => _n(20), cc => _f(33.33), dd => _s(77), ff => "food", gg => "0"},
    ],

    [ full => JSON::Schema::Fit->new(map {$_ => 1} @optional_opts),
        {aa => JSON::true, bb => _n(10), cc => _f(33.33), dd => _s(77), ee => _n(42), ff => "foo", gg => "0"},
    ],

    [ no_booleans => JSON::Schema::Fit->new(booleans => 0),
        {aa => 1, bb => _n(20), cc => _f(33.33), dd => _s(77), ff => "food", gg => "0"},
    ],
    [ no_rounding => JSON::Schema::Fit->new(round_numbers => 0),
        {aa => JSON::true, bb => _n(22), cc => _f(33.333333), dd => _s(77), ff => "food", gg => "0"},
    ],
    [ no_numbers => JSON::Schema::Fit->new(numbers => 0),
        {aa => JSON::true, bb => _s(22), cc => _s(33.333333), dd => _s(77), ff => "food", gg => "0"},
    ],
    [ no_strings => JSON::Schema::Fit->new(strings => 0),
        {aa => JSON::true, bb => _n(20), cc => _f(33.33), dd => _n(77), ff => "food", gg => "0"},
    ],
    [ no_hash_keys => JSON::Schema::Fit->new(hash_keys => 0),
        {aa => JSON::true, bb => _n(20), cc => _f(33.33), dd => _s(77), _debug => "stacktrace", ff => "food", gg => "0"},
    ],

    [ with_clamp_numbers => JSON::Schema::Fit->new(clamp_numbers => 1),
        {aa => JSON::true, bb => _n(10), cc => _f(33.33), dd => _s(77), ff => "food", gg => "0"},
    ],
    [ with_fill_defaults => JSON::Schema::Fit->new(fill_defaults => 1),
        {aa => JSON::true, bb => _n(20), cc => _f(33.33), dd => _s(77), ee => _n(42), ff => "food", gg => "0"},
    ],
    [ with_replace_invalid_enum => JSON::Schema::Fit->new(replace_invalid_enum => 1),
        {aa => JSON::true, bb => _n(20), cc => _f(33.33), dd => _s(77), ff => "foo", gg => "0"},
    ],

    [ disable_all => JSON::Schema::Fit->new(map {$_ => 0} @default_opts), $raw_data ],
);

for my $test ( @tests ) {
    my ($name, $jsf, $expected) = @$test;
    cmp_deeply $jsf->get_adjusted($raw_data, $schema), $expected, $name;
}


done_testing();
