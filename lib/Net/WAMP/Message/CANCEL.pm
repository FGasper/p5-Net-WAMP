package Net::WAMP::Message::CANCEL;

use strict;
use warnings;

use parent qw( Net::WAMP::Base::Message );

use constant PARTS => qw( Request  Metadata );

1;
