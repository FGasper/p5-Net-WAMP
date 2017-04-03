package Net::WAMP;

our $VERSION = '0.01';

=encoding utf-8

=head1 NAME

Net::WAMP - Support for Web Application Messaging Protocol (“WAMP”)

=head1 SYNOPSIS

A simple client:

    package My_Client;

    use strict; use warnings;

    #Your client can implement any or all of the following role classes:
    use parent (
        #“Producer” roles:
        'Net::WAMP::Role::Publisher',
        'Net::WAMP::Role::Callee',

        #“Consumer” roles:
        'Net::WAMP::Role::Subscriber',
        'Net::WAMP::Role::Caller',
    );

    #for the Subscriber class
    sub on_EVENT {
        my ($self, $msg_obj, $topic) = @_;
        ...
    }

    #for the Callee class
    sub on_INVOCATION {
        my ($self, $msg_obj, $procedure, $worker_obj) = @_;
        ...
    }

    #----------------------------------------------------------------------

    package main;

    my $client = My_Client->new(
        serialization => 'json',
        on_send => sub {
            my $serialized_bytes = shift;
            _send_serialized($serialized_bytes);
        },
    );

    $client->send_HELLO( 'my-realm' );

    my $msg = $client->handle_message( _read_from_transport() );

    #Do some sort of validation of the WELCOME message here …

    $client->send_PUBLISH(
        {},
        'com.haha.demo.chat',
        [ 'This is a message.' ],
    );

=head1 DESCRIPTION

This distribution provides support in Perl for the
L<Web Application Messaging Protocol (WAMP)|http://wamp-proto.org/>.

=head1 ALPHA STATUS

The WAMP standard itself is not yet finalized;
L<the current specification|http://wamp-proto.org/spec/> is a significant
revision
of an earlier proposed standard. That said, the details of it should be
pretty stable by this point; future changes to the core protocol should be
minor.

Also, several of the specification’s “Advanced” features are marked as
being in less-than-stable states.

Net::WAMP will attempt to accommodate any future updates to the protocol
with backward compatibility; however, at this point there are NO guarantees,
and you should absolutely check the changelog before updating.

=head1 HOW TO USE THIS FRAMEWORK

=head2 Roles

The role classes contain the role-specific logic for packaging and parsing
WAMP messages. Use multiple inheritance to govern which roles your application
will execute.

Your application will need to subclass one or more of the provided roles.
A given class must implement either client or router roles, but NOT both:

=head3 Client Roles:

=over

=item * L<Net::WAMP::Role::Publisher>

=item * L<Net::WAMP::Role::Subscriber>

=item * L<Net::WAMP::Role::Caller>

=item * L<Net::WAMP::Role::Callee>

=back

=head3 Router Roles:

=over

=item * L<Net::WAMP::Role::Broker>

=item * L<Net::WAMP::Role::Dealer>

=back

You can create custom handlers for individual message types by creating C<on_*>
methods in your subclasses; for example, if you want custom behavior on
PUBLISHED messages, you can subclass L<Net::WAMP::Role::Publisher> and define
C<on_PUBLISHED> on your class. Most handlers just receive the appropriate
Message object (more on these later); see the individual modules’
documentation for variances from that pattern.

=head2 I/O

To maximize flexibility, Net::WAMP does not read or write directly to
filehandles; instead, it accepts serialized messages (via the
C<handle_message()> method) and sends serialized messaged to a callback
function (C<on_send>).

For example, if you’re doing WAMP over WebSocket, you’ll feed each
WebSocket message’s payload into C<handle_message()> and set
C<on_send> to write its passed payload to WebSocket.

The expectation is that whatever transport layer you have underneath
WAMP—WebSocket, “L<RawSocket|Net::WAMP::RawSocket>”, or what have
you—receives data in the appropriate message chunks already
(see L<IO::Framed> for an example) and can “do the needful” with a
serialized message to send. This makes it possible to nest WAMP within
some other transport mechanism—even another messaging protocol!

=head3 WAMP “RawSocket”

Net::WAMP includes a full implementation of WAMP’s “RawSocket” protocol
in L<Net::WAMP::RawSocket>. This protocol is simpler than
WebSocket and is probably a better choice for communication between any
two WAMP nodes that can speak simple TCP. One limitation it imposes is a
hard upper limit on message size: if you think you might want to transmit
single messages of over 8 MiB, you’ll need some other transport mechanism
besides RawSocket.

=head3 Serializations

WAMP defines two serializations officially: L<JSON|http://json.org>
(C<json>)
and L<MessagePack|http://msgpack.org> (C<msgpack>). Net::WAMP only supports
JSON for now, though
L<MessagePack support should arrive soon|https://github.com/msgpack/msgpack-perl/issues/17>.

=head1 ROLE CLASSES

=head2 L<Net::WAMP::Role::Publish>

=over

=item * C<send_PUBLISH( METADATA_HR, TOPIC )>

=item * C<send_PUBLISH( METADATA_HR, TOPIC, ARGS_AR )>

=item * C<send_PUBLISH( METADATA_HR, TOPIC, ARGS_AR, ARGS_HR )>

=back

=head2 L<Net::WAMP::Role::Subscriber>

=over

=item * C<send_SUBSCRIBE( METADATA_HR, TOPIC )>

=item * C<send_UNSUBSCRIBE( SUBSCRIPTION_ID )>

=back

Also, you can create C<on_EVENT()> to handle published messages;
in addition to the EVENT message object, it also receives the subscribed TOPIC
as a separate parameter.

=head2 L<Net::WAMP::Role::Caller>

=over

=item * C<send_CALL( METADATA_HR, PROCEDURE )>

=item * C<send_CALL( METADATA_HR, PROCEDURE, ARGS_AR )>

=item * C<send_CALL( METADATA_HR, PROCEDURE, ARGS_AR, ARGS_HR )>

=back

=head2 L<Net::WAMP::Role::Callee>

=over

=item * C<send_YIELD( INVOCATION_ID, METADATA )>

=item * C<send_YIELD( INVOCATION_ID, METADATA, ARGS_AR )>

=item * C<send_YIELD( INVOCATION_ID, METADATA, ARGS_AR, ARGS_HR )>

=back

The C<on_INVOCATION()> callback receives two additional parameters after
the INVOCATION message object: the procedure name, and an instance of
L<Net::WAMP::RPCWorker()>. This object streamlines the process of sending
a response back to the caller.

=head1 MESSAGE CLASSES

Each message type has its own class. Each class has the following methods:

=head2 I<OBJ>->get( KEY )

Returns the value of the given key from the message. For all but one case,
the key should correspond to a value as given in the message type
definition in the protocol specification: for example,
C<HELLO> messages’s C<Realm> attribute.

The one exception to this correlation is the C<Details>/C<Options>
dictionaries.
You’ll notice that the WAMP specification defines either a C<Details> or
C<Options>
parameter for almost every message type. The logic behind this naming duality
is not
consistently applied; ostensibly C<Options> are for Client-to-Router while
C<Details> are for Router-to-Client, but HELLO messages contain C<Details>.
(??)
Regardless, the duality serves no practical purpose since no message can have
both C<Options> and C<Details>. In my opinion, this is just two names for the
same thing, which is just extra terminology to keep track of.
For these reasons, Net::WAMP
generalizes these names to C<Metadata>. If you like, you can still
use either of the other names for any of the message types that contains
either (i.e., you can use C<Options> with C<HELLO> just the same as
C<Details>).

=head2 I<OBJ>->get_type()

e.g., C<HELLO>, C<PUBLISHED>, …

=head1 SPECIFIC MESSAGE CLASSES

=over

=head2 Net::WebSocket::Message::PUBLISH

This class has methods C<publisher_wants_acknowledgement()> and
C<publisher_wants_to_be_excluded()> to indicate whether the given message
expresses
these desires. See the WAMP specification’s discussion of this message type
and the Publisher Exclusion feature for more details.

=head2 Net::WebSocket::Message::CALL

=head2 Net::WebSocket::Message::INVOCATION

Both of these have a C<caller_can_receive_progress()> method that returns a
boolean to indicate whether the caller indicated a willingness to receive
a progressive response to this specific remote procedure call. See the
WAMP specification’s discussion of the Progressive Call Results feature
for more information.

=head2 Net::WebSocket::Message::YIELD

=head2 Net::WebSocket::Message::RESULT

Both of these have an C<is_progress()> method that returns a
boolean to indicate whether this message will be followed by others for the
same CALL/INVOCATION. See the
WAMP specification’s discussion of the Progressive Call Results feature
for more information.

=back

=head1 ADVANCED PROFILE FEATURES

Net::WAMP supports some of WAMP’s Advanced Profile features. More may be
added at a later date; patches for at least the B<reasonably> stable features
are welcome. :)

=over

=item * C<publisher_exclusion> (publisher/broker feature)

=item * C<progressive_call_results> (RPC feature)

=back

=head1 TODO

Support more Advanced Profile features, especially:

=over

=item * call_canceling

=item * subscriber_blackwhite_listing

=back

=head1 REPOSITORY

L<https://github.com/FGasper/p5-Net-WAMP>

=head1 AUTHOR

Felipe Gasper (FELIPE)

=head1 COPYRIGHT

Copyright 2017 by L<Gasper Software Consulting, LLC|http://gaspersoftware.com>

=head1 LICENSE

This distribution is released under the same license as Perl.

=cut

1;
