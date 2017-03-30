package Net::WAMP;

our $VERSION = '0.01';

=encoding utf-8

=head1 NAME

Net::WAMP - Support for Web Application Messaging Protocol (“WAMP”)

=head1 SYNOPSIS

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
WAMP messages. This is where you can add your own custom handling of
received messages.

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

=head2 Transports

A Transport module implements the actual input/output of your WAMP application.
WAMP has two well-defined transport mechanisms:
L<WebSocket|https://tools.ietf.org/html/rfc6455>, and a custom protocol
that WAMP’s specification calls “RawSocket”. As their names imply, you’ll
likely favor the former for web connections and the latter for non-web
connections.

The demands of your specific application may require that you write a custom
Transport module; there is documentation at L<Net::WAMP::Transport> for writing
custom Transport modules.

The built-in Transport modules here are:

=over

=item * L<Net::WAMP::Transport::WebSocket>

WAMP’s standard transport protocol.

=item * L<Net::WAMP::Transport::RawSocket>

A WAMP-specific transport protocol. It’s simpler and a bit lighter.
Routers can even receive RawSocket connections on the same port as
WebSocket connections (cf. L<Net::WAMP::Transport::CheckSocket>)

=item * L<Net::WAMP::Transport::Queue>

A sort of “null” transport, suitable for contexts where a framework
accepts/gives WAMP’s serialized payloads. (e.g., event loops) This doesn’t
require an I/O object like WebSocket or RawSocket.

=back

=head2 I/O

Stream-based Transport objects require an I/O object to do the actual transfer
of bytes into and out of WAMP. Net::WAMP includes the following I/O objects:

=over

=item * L<Net::WAMP::Transport::IO::NonBlocking>

Non-blocking I/O. Versatile for both routers and clients.

=item * L<Net::WAMP::Transport::IO::Blocking>

Blocking I/O. This may simplify writing clients but won’t work for a router
unless you’re going to fork.

=back

=head2 Serializations

WAMP defines two serializations officially: L<JSON|http://json.org>
and L<MessagePack|http://msgpack.org>. JSON is supported now, and
L<MessagePack support should arrive soon|https://github.com/msgpack/msgpack-perl/issues/17>.

=head1 MESSAGE CLASSES

Each message type has its own class. Each class has the following methods:

=head2 I<OBJ>->get( KEY )

Returns the value of the given key from the message. The key should correspond
to a value as given in the message type definition in the protocol; for example,
C<HELLO> messages have both C<Realm> and … well, C<Metadata>.

You’ll notice that the WAMP specification defines either a C<Details> or
C<Options>
parameter for almost every message type. The logic behind this naming is not
consistently applied, and the duality serves no practical purpose; hence,
Net::ACME generalizes these names to C<Metadata>. If you like, you can still
use either of the other names for any of the message types that contains
either (i.e., you can use C<Options> with C<HELLO> just the same as
C<Details>).

=head2 I<OBJ>->get_type()

e.g., C<HELLO>, C<PUBLISHED>, …

=head1 ADVANCED PROFILE FEATURES

Net::WAMP supports some of WAMP’s Advanced Profile features. More may be
added at a later date; patches for at least the B<reasonably> stable features
are welcome. :)

=over

=item * C<publisher_exclusion> (publisher/broker feature)

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
