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
requires 'IO::Uncompress::Gunzip' => 2.055;

tests 't/*.t';
author_tests 'xt';

build_requires 'Test::More';
build_requires 'File::Copy::Recursive';
build_requires 'File::Path';
build_requires 'IO::Compress::Gzip' => 2.055;

auto_set_repository;
auto_include;
WriteAll;
