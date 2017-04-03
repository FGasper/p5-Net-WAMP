package Net::WAMP::Message::ERROR;

use strict;
use warnings;

use Net::WAMP::Messages ();

use parent qw( Net::WAMP::Base::Message );

use constant PARTS => qw( Type  Request  Metadata  Error  Arguments  ArgumentsKw );

sub get_request_type {
    my ($self) = @_;

    return Net::WAMP::Messages::get_type( $self->get('Type') );
}

1;
