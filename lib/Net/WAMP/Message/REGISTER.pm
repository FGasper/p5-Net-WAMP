package Net::WAMP::Message::REGISTER;

use parent qw( Net::WAMP::SessionMessage );

use constant PARTS => qw( Request  Options  Procedure );

1;
