package Net::WAMP::Client::CanError;

use strict;
use warnings;

use parent qw( Net::WAMP::Client );

use Try::Tiny;

sub _create_and_send_ERROR {
    my ($self, $subtype, @args) = @_;

    return $self->_create_and_send_msg(
        'ERROR',
        Protocol::WAMP::Messages::get_type_number($subtype),
        @args,
    );
}

sub _catch_exception {
    my ($self, $req_type, $req_id, $todo_cr) = @_;

    my $ret;

    try {
        $ret = $todo_cr->();
    }
    catch {
        $self->_create_and_send_ERROR(
            $req_type,
            $req_id,
            {},
            'net-wamp.error.exception',
            [ "$_" ],
        );
    };

    return $ret;
}

1;
