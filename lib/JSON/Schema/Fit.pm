package JSON::Schema::Fit;

# ABSTRACT: adjust data structure according to json-schema

=head1 SYNOPSIS

    my $data = get_dirty_result();
    # raw data: got { num => "1.99999999997", flag => "1", junk => {...} }
    my $bad_json = encode_json $data;
    # {"num":"1.99999999997","flag":"1","junk":{...}}

    # JSON::Schema-compatible
    my $schema = { type => 'object', additionalProperties => 0, properties => {
        num => { type => 'integer' },
        flag => { type => 'boolean' },
    }};
    my $prepared_data = JSON::Schema::Fit->new()->get_adjusted($data, $schema);
    my $cool_json = encode_json $prepared_data;
    # {"num":2,"flag":true}

=head1 DESCRIPTION

The main goal of this package is preparing data to be encoded as json according to schema.

Actions implemented:
adjusting value type (number/string/boolean),
rounding numbers,
filtering hash keys.

=head1 CONSTRUCTOR

=method new

    my $jsf = JSON::Schema::Fit->new(booleans => 0);

Create a new C<JSON::Schema::Fit> instance. See bellow for valid options.

=head1 SEE ALSO

Related modules: L<JSON>, L<JSON::Schema>.

Json-schema home: L<http://json-schema.org/>

=cut

use 5.010;
use strict;
use warnings;
use utf8;

use Carp;

use JSON;
use Storable;
use Scalar::Util qw/reftype/;
use List::Util qw/first none/;
use Math::Round qw/round nearest/;



=attr booleans

Explicitly set type for boolean values to JSON::true / JSON::false

Default: 1

=cut

sub booleans { return _attr('booleans', @_); }

=attr numbers

Explicitly set type for numeric and integer values

Default: 1

=cut

sub numbers { return _attr('numbers', @_); }


=attr round_numbers

Round numbers according to 'multipleOf' schema value

Default: 1

=cut

sub round_numbers { return _attr('round_numbers', @_); }

=attr clamp_numbers

Crop numbers accordingly with 'maximum', 'minimum' attributes.

Values outside these limits will be set to the defined in the maximum/minimum
attributes. 

Default: 0

=cut

sub clamp_numbers { return _attr('clamp_numbers', @_); }


=attr strings

Explicitly set type for strings

Default: 1

=cut

sub strings { return _attr('strings', @_); }

=attr hash_keys

Filter out not allowed hash keys (where additionalProperties is false).

Default: 1

=cut

sub hash_keys { return _attr('hash_keys', @_); }


=attr fill_defaults

Fill missing values that have 'default' attribute in schema.

Default: 0

=cut

sub fill_defaults { return _attr('fill_defaults', @_); }

=attr replace_invalid_values

Replace incompatible with schema values with defaults (if defined).
For now, only presence in 'enum' is checked.

Default: 0

=cut

sub replace_invalid_values { return _attr('replace_invalid_values', @_); }



# Store valid options as well as default values
my %valid_option =(
    ( map { ($_ => 1) } qw!booleans numbers round_numbers strings hash_keys! ),
    ( map { ($_ => 0) } qw!clamp_numbers fill_defaults replace_invalid_values! ),
);

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;
    for my $k (keys %opts) {
        next unless exists $valid_option{$k};
        _attr($k, $self, $opts{$k});
    }
    return $self
}

sub _attr {
    my $attr = shift;
    my $self = shift;

    if (@_) {
        return $self->{$attr} = shift;
    } else {
        return $self->{$attr} //= $valid_option{$attr};
    }
}

=method get_adjusted

Returns "semi-copy" of data structure with adjusted values. Original data is not affected.

=cut

sub get_adjusted {
    my ($self, $struc, $schema, $jpath) = @_;

    return $struc  if !ref $schema || reftype $schema ne 'HASH';

    if (
        exists $schema->{default} && (
            !defined $struc && $self->fill_defaults ||
            $self->replace_invalid_values && !$self->_is_valid($struc, $schema)
        )
    ) {
        return $self->_default_value($schema);
    }

    my $method = $self->_adjuster_by_type($schema->{type});
    return $struc  if !$method;
    return $self->$method($struc, $schema, $jpath);
}


sub _is_valid {
    my ($self, $struc, $schema) = @_;

    if (my $enum = $schema->{enum}) {
        return '' if none {my $v = $_; $struc eq $v} @$enum;
    }

    return 1;


    return grep { Compare($struc, $_) } @{$schema->{enum}};
}


sub _default_value {
    my ($self, $schema) = @_;
    return if !exists $schema->{default};

    my $default = $schema->{default};
    return ref $default ? Storable::dclone($default) : $default;
}


sub _adjuster_by_type {
    my ($self, $type) = @_;

    return if !$type;
    my $method = "_get_adjusted_$type";
    return $method if $self->can($method);
    return;
}


sub _get_adjusted_boolean {
    my ($self, $struc, $schema, $jpath) = @_;

    return $struc if !$self->booleans();
    return JSON::true if $struc;
    return JSON::false;
}


sub _get_adjusted_integer {
    my ($self, $struc, $schema, $jpath) = @_;

    return $struc  if !$self->numbers();
    my $result = $self->_get_adjusted_number($struc, $schema, $jpath);
    return round($result);
}


sub _get_adjusted_number {
    my ($self, $struc, $schema, $jpath) = @_;

    return $struc  if !$self->numbers();
    my $result = 0+$struc;

    if ($self->round_numbers) {
        my $quantum = $schema->{multipleOf} || $schema->{divisibleBy};
        $result = nearest $quantum, $result if $quantum;
    }

    if ($self->clamp_numbers) {
        $result = $schema->{maximum} if exists $schema->{maximum} and $result > $schema->{maximum};
        $result = $schema->{minimum} if exists $schema->{minimum} and $result < $schema->{minimum};
    }

    return $result;
}


sub _get_adjusted_string {
    my ($self, $struc, $schema, $jpath) = @_;

    return $struc  if !$self->strings();
    return "$struc";
}


sub _get_adjusted_array {
    my ($self, $struc, $schema, $jpath) = @_;

    croak "Structure is not ARRAY at $jpath"  if reftype $struc ne 'ARRAY';

    my $result = [];
    for my $i ( 0 .. $#$struc ) {
        push @$result, $self->get_adjusted($struc->[$i], $schema->{items}, $self->_jpath($jpath, $i));
    }

    return $result;
}

sub _get_adjusted_object {
    my ($self, $struc, $schema, $jpath) = @_;

    croak "Structure is not HASH at $jpath"  if reftype $struc ne 'HASH';

    my $result = {};
    my $keys_re;

    my $properties = $schema->{properties} || {};
    my $p_properties = $schema->{patternProperties} || {};

    if ($self->hash_keys() && exists $schema->{additionalProperties} && !$schema->{additionalProperties}) {
        my $keys_re_text = join q{|}, (
            keys %$p_properties,
            map {quotemeta} keys %$properties,
        );
        $keys_re = qr{^$keys_re_text$}x;
    }

    for my $key (keys %$struc) {
        next if $keys_re && $key !~ $keys_re;

        my $subschema = $properties->{$key};
        if (my $re_key = !$subschema && first {$key =~ /$_/x} keys %$p_properties) {
            $subschema = $p_properties->{$re_key};
        }

        $result->{$key} = $self->get_adjusted($struc->{$key}, $subschema, $self->_jpath($jpath, $key));
    }

    if ($self->fill_defaults) {
        for my $key (keys %$properties) {
            next if exists $result->{$key};
            my $subschema = $properties->{$key};
            next if !exists $subschema->{default};
            $result->{$key} = $self->_default_value($subschema);
        }
    }

    return $result;
}


sub _jpath {
    my ($self, $path, $key) = @_;
    $path //= q{$};

    return "$path.$key"  if $key =~ /^[_A-Za-z]\w*$/x;

    $key =~ s/(['\\])/\\$1/gx;
    return $path . "['$key']";
}


1;

