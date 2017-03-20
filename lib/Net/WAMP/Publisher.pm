package Net::WAMP::Publisher;

use strict;
use warnings;

use parent qw(
    Net::WAMP::Client
    Net::WAMP::SessionScope
);

use File::Spec ();
use Module::Load ();

use Types::Serialiser ();

use lib '/Users/felipe/code/p5-Protocol-WAMP/lib';

use constant {
    receiver_role_of_PUBLISH => 'broker',
};

use Net::WAMP::Client::Features ();

BEGIN {
    $Net::WAMP::Client::Features::FEATURES{'publisher'}{'features'}{'publisher_exclusion'} = $Types::Serialiser::true;
}

sub send_PUBLISH {
    my ($self, $opts_hr, $topic, @args) = @_;

    if (!$self->peer_is('broker')) {
        die "Peer is not a broker; can’t publish!";
    }

    #local $opts_hr->{'acknowledge'} = ${ *{$Types::Serialiser::{ $opts_hr->{'acknowledge'} ? 'true' : 'false' }}{'SCALAR'} } if exists $opts_hr->{'acknowledge'};

    my $req_id = $self->_get_next_session_scope();

    my $msg = $self->_create_and_send_msg(
        'PUBLISH',
        $req_id,
        $opts_hr,
        $topic,
        @args,
    );

    $self->{'_sent_PUBLISH'}{$req_id} = $msg;

    return $msg;
}

sub _receive_PUBLISHED {
    my ($self, $msg) = @_;

    if (!delete $self->{'_sent_PUBLISH'}{ $msg->get('Request') }) {
        die sprintf("Received PUBLISHED for unknown! (%s)", $msg->get('Request')); #XXX
    }

    return;
}

1;
