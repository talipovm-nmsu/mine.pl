%nproc=44
%mem=60Gb
%chk=SQ-c1.chk
#p M062X/6-31+G(d)   opt(tight)
int(grid=ultrafine) scf(xqc,fermi,maxcyc=200)
scrf(smd,solvent=water) 


0 2
@SQ-c1.xyz

 $nbo archive file=SQ-c1 $end

--link1--
%nproc=44
%mem=60Gb
%chk=SQ-c1.chk
#p M062X/6-31+G(d)  stable(opt) pop(nbo)
int(grid=ultrafine) scf(xqc,fermi,maxcyc=200)
scrf(check) guess(read) geom(allcheck) 

--link1--
%nproc=44
%mem=60Gb
%chk=SQ-c1.chk
#p M062X/6-31+G(d)  freq
int(grid=ultrafine) scf(xqc,fermi,maxcyc=200)
scrf(check) guess(read) geom(allcheck) 

--link1--
%nproc=44
%mem=60Gb
%chk=SQ-c1.chk
#p M062X/6-31+G(d)  td(nstates=10)
int(grid=ultrafine) scf(xqc,fermi,maxcyc=200)
scrf(check) guess(read) geom(allcheck) 


