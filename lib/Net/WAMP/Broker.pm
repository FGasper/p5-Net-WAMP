package Net::WAMP::Broker;

use strict;
use warnings;

use Types::Serialiser ();

use Net::WAMP::Router::Features ();

BEGIN {
    $Net::WAMP::Router::Features::FEATURES{'broker'}{'features'}{'publisher_exclusion'} = $Types::Serialiser::true;

    return;
}

sub subscribe {
    my ($self, $io, $options, $topic) = @_;

    my $realm = $self->_get_realm_for_io($io);

    if ($self->{'_realm_topic_subscribers'}{$realm}{$topic}{$io}) {
        die "Already subscribed!";
    }

    my $subscription = Protocol::WAMP::Utils::generate_global_id();

    $self->{'_realm_topic_subscribers'}{$realm}{$topic}{$io} = {
        io => $io,
        options => $options,
        subscription => $subscription,
    };

    $self->{'_realm_subscription_topic'}{$realm}{$subscription} = $topic;

    return $subscription;
}

sub unsubscribe {
    my ($self, $io, $subscription) = @_;

    my $realm = $self->_get_realm_for_io($io);

    my $topic = delete $self->{'_realm_subscription_topic'}{$realm}{$subscription} or do {
        die "No subscription found!";
    };

    delete $self->{'_realm_topic_subscribers'}{$realm}{$topic}{$io};

    return;
}

sub publish {
    my ($self, $io, $options, $topic, $args_ar, $args_hr) = @_;

    my $realm = $self->_get_realm_for_io($io);

    my @recipients = values %{ $self->{'_realm_topic_subscribers'}{$realm}{$topic} };

    my $publication = Protocol::WAMP::Utils::generate_global_id();

    for my $rcp (@recipients) {
        $self->send_EVENT(
            $rcp->{'io'},
            $rcp->{'subscription'},
            $publication,
            {}, #TODO ???
            ( $args_ar ? ( $args_ar, $args_hr || () ) : () ),
        );
    }

    return $publication;
}

1;
