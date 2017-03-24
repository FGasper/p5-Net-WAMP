package Net::WAMP::Message;

use strict;
use warnings;

use Net::WAMP::Messages ();

sub new {
    my ($class, @args) = @_;

    my @parts = $class->PARTS();

    my $self = { map { ( "_$parts[$_]" => $args[$_] ) } 0 .. $#args };

    return bless $self, $class;
}

sub get {
    my ($self, $key) = @_;

    if (grep { $_ eq $key } $self->PARTS()) {
        return $self->{"_$key"};
    }

    my $name = $self->get_type();
    die "Unrecognized attribute of “$name” message: “$key”";
}

sub get_type {
    my ($self) = @_;

    ref($self) =~ m<.+::(.+)> or die "module name ($self)??";

    return $1;
}

sub to_unblessed {
    my ($self) = @_;

    my @msg = (
        Net::WAMP::Messages::get_type_number( $self->get_type() ),
        ( map { exists($self->{"_$_"}) ? $self->{"_$_"} : () } $self->PARTS() ),
    );

    return \@msg;
}

1;
