use strict;
use Test::More;

use Plack::Test;
use HTTP::Request::Common;

BEGIN { use_ok 'Plack::App::GitSmartHttp' }

my $app = Plack::App::GitSmartHttp->new(
    root          => "t/test_repos",
    upload_pack   => 1,
    received_pack => 1,
);

test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/repo1/HEAD" );
    is $res->code, 200;
    is length( $res->decoded_content ), length("ref: refs/heads/master\n");
};

done_testing
