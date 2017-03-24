package Net::WAMP::Message::SUBSCRIBE;

use parent qw( Net::WAMP::SessionMessage );

use constant PARTS => qw( Request  Options  Topic );

1;
