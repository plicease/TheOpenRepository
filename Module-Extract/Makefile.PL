use inc::Module::Install;

name          'Module-Extract';
all_from      'lib/Module/Extract.pm';
requires      'Carp'             => 0;
requires      'File::Path'       => '1.06';
requires      'File::Temp'       => '0.17';
requires      'Archive::Extract' => '0.18';
test_requires 'File::Spec'       => '0.80';
test_requires 'Test::More'       => '0.42';

WriteAll;
