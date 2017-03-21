package Net::WAMP::Subscriber;

use strict;
use warnings;

use parent qw(
    Net::WAMP::Client
    Net::WAMP::SessionScope
);

use Module::Load ();

use lib '/Users/felipe/code/p5-Protocol-WAMP/lib';

use constant {
    receiver_role_of_SUBSCRIBE => 'broker',
    receiver_role_of_UNSUBSCRIBE => 'broker',
};

sub send_SUBSCRIBE {
    my ($self, $opts_hr, $topic) = @_;

    my $msg = $self->_create_and_send_session_msg(
        'SUBSCRIBE',
        $opts_hr,
        $topic,
    );

    $self->{'_sent_SUBSCRIBE'}{$req_id} = $msg;

    return $msg;
}

sub send_UNSUBSCRIBE {
    my ($self, $subscription_id) = @_;

    my $msg = $self->_create_and_send_session_msg(
        'UNSUBSCRIBE',
        $subscription_id,
    );

    $self->{'_sent_UNSUBSCRIBE'}{$req_id} = $msg;

    return $msg;
}

sub _receive_SUBSCRIBED {
    my ($self, $msg) = @_;

    my $req_id = $msg->get('Request');

    my $orig_subscr = delete $self->{'_sent_SUBSCRIBE'}{ $req_id };

    if (!$orig_subscr) {
        die "Received SUBSCRIBED for unknown (Request=$req_id)!"; #XXX
    }

    $self->{'_subscriptions'}{ $msg->get('Subscription') } = $orig_subscr->get('Topic');

    return;
}

sub _receive_UNSUBSCRIBED {
    my ($self, $msg) = @_;

    if (my $omsg = delete $self->{'_sent_UNSUBSCRIBE'}{ $msg->get('Request') }) {
        delete $self->{'_subscriptions'}{ $omsg->{'Subscription'} };
    }
    else {
        die "Received UNSUBSCRIBED for unknown!"; #XXX
    }

    return;
}

sub _receive_EVENT {
    my ($self, $msg) = @_;

    my $subscr_id = $msg->get('Subscription');

    my $topic = $self->{'_subscriptions'}{ $subscr_id };

    if (!$topic) {
        die "Received EVENT for unknown (Subscription=$subscr_id)!"; #XXX
    }

    return $topic;
}

1;
