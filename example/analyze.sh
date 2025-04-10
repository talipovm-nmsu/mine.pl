#!/usr/bin/env zsh


echo 'Checking which isomer is more stable'
../mine.pl --terse --td scf di-tBu-quinone/SQ-c*log

echo

echo 'Compute the energy of a proton transfer from 3,5-di-tBu-HQ and 1,2-Q'
echo '--Electronic Energy--'
../mine.pl --terse --kJ --td scf \
    --g1 o-quinone/SQ.log --g1 di-tBu-quinone/Q-AR.log \
    --g2 o-quinone/Q-AR.log --g2 di-tBu-quinone/SQ-c2.log

echo
echo '--Free Energy--'
../mine.pl --terse --kJ --td Gibbs \
    --g1 o-quinone/SQ.log --g1 di-tBu-quinone/Q-AR.log \
    --g2 o-quinone/Q-AR.log --g2 di-tBu-quinone/SQ-c2.log

