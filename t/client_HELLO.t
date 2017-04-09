#!/usr/bin/env perl

use strict;
use warnings;

use Test::Deep;
use Test::More tests => 1;

use Types::Serialiser ();

use Net::WAMP::Session ();

#----------------------------------------------------------------------
package MyClient;

#just picked one …
use parent qw( Net::WAMP::Role::Publisher );

#----------------------------------------------------------------------

package main;

my @sent;

my $client = MyClient->new(
    serialization => 'json',
    on_send => sub { push @sent, $_[0] },
);

$client->send_HELLO( 'my-realm', { foo => 2 } );

#Use this just for serialization. This isn’t needed in actual code.
my $json_session = Net::WAMP::Session->new(
    serialization => 'json',
    on_send => sub { die 'NONO' },
);

my $hello_msg = $json_session->message_bytes_to_object( shift @sent );

cmp_deeply(
    $hello_msg,
    all(
        Isa('Net::WAMP::Message::HELLO'),
        methods(
            [ get => 'Realm' ] => 'my-realm',
            [ get => 'Metadata' ] => {
                foo => 2,
                agent => re( qr<MyClient> ),
                roles => {
                    publisher => {
                        features => {
                            publisher_exclusion => Types::Serialiser::true(),
                        },
                    },
                },
            },
        ),
    ),
    'HELLO messsage sent as expected',
) or diag explain $hello_msg;
