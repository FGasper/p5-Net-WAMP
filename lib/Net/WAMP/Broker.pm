package Net::WAMP::Broker;

use strict;
use warnings;

use Types::Serialiser ();

use Net::WAMP::Router::Features ();
use Protocol::WAMP::Utils ();

BEGIN {
    $Net::WAMP::Router::Features::FEATURES{'broker'}{'features'}{'publisher_exclusion'} = $Types::Serialiser::true;

    return;
}

sub subscribe {
    my ($self, $tpt, $options, $topic) = @_;

    my $subscribers_hr = $self->_get_topic_subscribers($tpt, $topic);

    if ($subscribers_hr->{$tpt}) {
        die "Already subscribed!";
    }

    my $subscription = Protocol::WAMP::Utils::generate_global_id();

    $self->{'_state'}->set_realm_deep_property(
        $tpt,
        [ "subscribers_$topic", $tpt ],
        {
            tpt => $tpt,
            options => $options,
            subscription => $subscription,
        },
    );

    $self->{'_state'}->set_realm_property( $tpt, "subscription_topic_$subscription", $topic );

    return $subscription;
}

sub unsubscribe {
    my ($self, $tpt, $subscription) = @_;

    my $topic = $self->{'_state'}->unset_realm_property($tpt, "subscription_topic_$subscription") or do {
        my $realm = $self->_get_realm_for_tpt($tpt);
        die "Realm “$realm” has no subscription for ID “$subscription”!";
    };

    $self->{'_state'}->unset_realm_deep_property(
        $tpt, [ "subscribers_$topic", $tpt ],
    );

    return;
}

sub publish {
    my ($self, $tpt, $options, $topic, $args_ar, $args_hr) = @_;

    my $subscribers_hr = $self->_get_topic_subscribers($tpt, $topic);

    my $publication = Protocol::WAMP::Utils::generate_global_id();

    for my $rcp (values %$subscribers_hr) {

        #Implements “Publisher Exclusion” feature
        if ( $tpt eq $rcp->{'tpt'} ) {
            next if !Types::Serialiser::is_false($options->{'exclude_me'});
            my $exclusion = $self->{'_state'}->get_transport_property($tpt, 'peer_roles')->{'publisher'}{'features'}{'publisher_exclusion'};
            next if !Types::Serialiser::is_true($exclusion);
        }

        $self->_send_EVENT(
            $rcp->{'tpt'},
            $rcp->{'subscription'},
            $publication,
            {}, #TODO ???
            ( $args_ar ? ( $args_ar, $args_hr || () ) : () ),
        );
    }

    return $publication;
}

sub _get_topic_subscribers {
    my ($self, $tpt, $topic) = @_;

    return $self->{'_state'}->get_realm_property($tpt, "subscribers_$topic");
}

#sub _get_topic_subscribers_or_die {
#    my ($self, $tpt, $topic) = @_;
#
#    return $self->_get_topic_subscribers($tpt, $topic) || do {
#        my $realm = $self->_get_realm_for_tpt($tpt);
#        die "Realm “$realm” has no topic “$topic”!";
#    };
#}

#----------------------------------------------------------------------

sub _receive_SUBSCRIBE {
    my ($self, $tpt, $msg) = @_;

    my $subscription = $self->subscribe(
        $tpt,
        ( map { $msg->get($_) } qw( Options Topic ) ),
    );

    return $self->_send_SUBSCRIBED(
        $tpt,
        $msg->get('Request'),
        $subscription,
    );
}

sub _send_SUBSCRIBED {
    my ($self, $tpt, $req_id, $sub_id) = @_;

    return $self->_create_and_send_msg(
        $tpt,
        'SUBSCRIBED',
        $req_id,
        $sub_id,
    );
}

sub _receive_UNSUBSCRIBE {
    my ($self, $tpt, $msg) = @_;

    $self->unsubscribe(
        $tpt,
        $msg->get('Subscription'),
    );

    $self->_send_UNSUBCRIBED( $tpt, $msg->get('Request') );

    return;
}

sub _send_UNSUBSCRIBED {
    my ($self, $tpt, $req_id) = @_;

    return $self->_create_and_send_msg(
        $tpt,
        'UNSUBSCRIBED',
        $req_id,
    );
}

sub _receive_PUBLISH {
    my ($self, $tpt, $msg) = @_;

    my $publication = $self->publish(
        $tpt,
        map { $msg->get($_) } qw(
            Options
            Topic
            Arguments
            ArgumentsKw
        ),
    );

    if (Types::Serialiser::is_true($msg->get('Options')->{'acknowledge'})) {
        $self->_send_PUBLISHED(
            $tpt,
            $msg->get('Request'),
            $publication,
        );
    }

    return;
}

sub _send_PUBLISHED {
    my ($self, $tpt, $req_id, $pub_id) = @_;

    return $self->_create_and_send_msg(
        $tpt,
        'PUBLISHED',
        $req_id,
        $pub_id,
    );
}

sub _send_EVENT {
    my ($self, $tpt, $sub_id, $pub_id, $details, @args) = @_;

    return $self->_create_and_send_msg(
        $tpt,
        'EVENT',
        $sub_id,
        $pub_id,
        $details,
        @args,
    );
}

1;
