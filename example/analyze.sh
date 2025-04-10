#!/usr/bin/env zsh


echo 'SQ-c2 should be more stable, change the script if it is not the case'
../mine.pl --terse --td scf di-tBu-quinone/SQ-c*log

echo
echo '--Electronic Energy--'
echo 'Check the value, it is expected to be around or less than 10 kJ/mol to be consistent with the experiment'
../mine.pl --terse --kJ --td scf \
    --g1 o-quinone/SQ.log --g1 di-tBu-quinone/Q-AR.log \
    --g2 o-quinone/Q-AR.log --g2 di-tBu-quinone/SQ-c2.log

echo
echo '--Free Energy--'
echo 'Check the value, it is expected to be around or less than 10 kJ/mol to be consistent with the experiment'
../mine.pl --terse --kJ --td Gibbs \
    --g1 o-quinone/SQ.log --g1 di-tBu-quinone/Q-AR.log \
    --g2 o-quinone/Q-AR.log --g2 di-tBu-quinone/SQ-c2.log

