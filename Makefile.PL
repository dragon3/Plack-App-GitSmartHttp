use inc::Module::Install;
name 'Plack-App-GitSmartHttp';
all_from 'lib/Plack/App/GitSmartHttp.pm';

requires 'parent';
requires 'Plack';
requires 'HTTP::Date';
requires 'Cwd';
requires 'File::Spec';
requires 'File::chdir';
requires 'File::Which';
requires 'IPC::Open3';

tests 't/*.t';
author_tests 'xt';

build_requires 'Test::More';

auto_set_repository;
auto_include;
WriteAll;
