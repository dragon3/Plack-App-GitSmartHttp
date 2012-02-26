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
    my $res = $cb->(
        POST "/repo1/git-upload-pack",
        "Content-Type" => "application/x-git-upload-pack-request"
    );
    is $res->code, 200;
    is $res->header("Content-Type"), 'application/x-git-upload-pack-result';
};

done_testing
