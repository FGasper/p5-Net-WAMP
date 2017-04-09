package Net::WAMP::Message::INTERRUPT;

use strict;
use warnings;

use parent qw( Net::WAMP::Base::Message );

use constant PARTS => qw( Request  Metadata );

use constant NUMERIC => qw( Request );

1;
