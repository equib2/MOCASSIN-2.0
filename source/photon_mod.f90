! Copyright (C) 2005 Barbara Ercolano 
! 
! Version 2.02
module photon_mod
    
    use common_mod
    use constants_mod
    use continuum_mod
    use grid_mod
    use interpolation_mod
    use pathIntegration_mod
    use vector_mod

    ! common variables 

    real :: Qphot = 0.


    type(vector), parameter :: origin=vector(0.,0.,0.)  ! origin of the cartesian grid axes

    integer     , parameter :: safeLim = 10000          ! safety limit for the loops
    integer                        :: totalEscaped  

    contains

    subroutine energyPacketDriver(iStar, n, grid, plot, gpLoc, cellLoc)
        implicit none
        
        integer, intent(in)            :: n           ! number of energy packets 
        integer, intent(in)            :: iStar       ! central star index 

        integer, intent(inout), optional &
             & :: gpLoc                               ! local grid (only used for extra diffuse sources)
        integer, intent(inout), optional &
             & :: cellLoc(3)                          ! local cell (only used for extra diffuse sources)
       
        type(plot_type), intent(inout), optional &
             & :: plot                                ! only used in the mocassinPlot version
        type(grid_type), dimension(:), intent(inout) :: grid        ! the grid(s)
        
        type(vector)                   :: posVector   ! initial position vector for dust emi

        ! local variables
        integer                        :: igp         ! 1= mother 2 =sub 
        integer                        :: ian         ! angle counter
        integer                        :: ifreq       ! freq counter
        integer                        :: iview       ! viewing angle counter
        integer                        :: freqP       ! pointer to frequency
        integer                        :: i,j,k,iG,ii ! counters        
        integer                        :: iCell       ! cell counter
        integer                        :: igrid,ix,iy,iz ! location indeces
        integer                        :: ierr        ! allocation error status
        integer                        :: iPhot       ! counter
        integer                        :: plotNum     ! counter
        integer                        :: seedSize    ! pseudo random number generator seed 
        integer, dimension(2)          :: inX,inY,inZ ! initial position indeces
        integer, pointer               :: seed(:)     ! seed array
        integer                        :: msec        ! millisecs of the sec
        integer                        :: dt(8)       ! date and time values

        real                           :: JDifTot     ! tot JDif
        real                           :: JsteTot     ! tot Jste
        real                           :: radius      ! radius
        


        character(len=7)               :: chTypeD     ! character type for driver

        type(vector)                   :: absPosition ! position of packet absorption


        if (iStar == 0) then
           deltaE(0) = grid(gpLoc)%LdiffuseLoc(grid(gpLoc)%active(cellLoc(1),cellLoc(2),cellLoc(3)))/NphotonsDiffuseLoc
        end if

        call date_and_time(values=dt)
        msec=dt(8)

        call random_seed(seedSize) 

        allocate(seed(1:seedSize), stat= ierr)
        if (ierr /= 0) then
            print*, "energyPacketDriver: can't allocate array memory: seed"
            stop
        end if

        seed = 0

        call random_seed(get = seed)
 
        seed = seed + msec + taskid

        call random_seed(put = seed)
        
        if (associated(seed)) deallocate(seed)

        Qphot = 0.

        do iPhot = 1, n

           if (iStar>=1) then

              chTypeD = "stellar"              
              

              call energyPacketRun(chTypeD, starPosition(iStar))

           else if (iStar==0) then

              chTypeD = "diffExt"              
              inX=-1
              inY=-1
              inZ=-1
              inX(gpLoc) = cellLoc(1)
              inY(gpLoc) = cellLoc(2)
              inZ(gpLoc) = cellLoc(3)

              call energyPacketRun(chType=chTypeD, xp=inX, & 
                   & yp=inY, zp=inZ, gp=gpLoc)

           else

              print*, '! energyPacketDriver: insanity in iStar value'
              stop

           end if
        end do

        if (iStar>0) then
           print*, 'Star: ', iStar
           print*, 'Qphot = ', Qphot
        end if


        if (lgDust.and.convPercent>=resLinesTransfer .and.&
             & .not.lgResLinesFirst&
             & .and. (.not.nIterateMC==1)) then

           print*, "! energyPacketDriver: starting resonance line packets transfer"


           iCell = 0
           do igrid = 1, nGrids

              if (igrid==1) then
                 igp = 1
              else if (igrid>1) then
                 igp = 2
              else
                 print*, "! energyPacketDriver: insane grid pointer"
                 stop
              end if


              do ix = 1, grid(igrid)%nx
                 do iy = 1, grid(igrid)%ny
                    do iz = 1, grid(igrid)%nz
                       iCell = iCell+1

                       if (mod(iCell-(taskid+1),numtasks)==0) then
                          if (grid(igrid)%active(ix,iy,iz)>0) then

                             do iPhot = 1, grid(igrid)%resLinePackets(grid(igrid)%active(ix,iy,iz))

                                chTypeD = "diffuse"
                                posVector%x = grid(igrid)%xAxis(ix)
                                posVector%y = grid(igrid)%yAxis(iy)
                                posVector%z = grid(igrid)%zAxis(iz)
                                
                                inX=-1
                                inY=-1
                                inZ=-1
                                inX(igp)=ix
                                inY(igp)=iy
                                inZ(igp)=iz
                                
                                if (igrid>1) then
                                   ! check location on mother grid
                                   call locate(grid(grid(igrid)%motherP)%xAxis, &
                                        & posVector%x,inX(1))
                                   if (posVector%x > (grid(grid(igrid)%motherP)%xAxis(inX(1))+&
                                        & grid(grid(igrid)%motherP)%xAxis(inX(1)+1) )/2.) &
                                        & inX(1) = inX(1)+1                                   
                                   call locate(grid(grid(igrid)%motherP)%yAxis, &
                                        & posVector%y,inY(1))
                                   if (posVector%y > (grid(grid(igrid)%motherP)%yAxis(inY(1))+&
                                        & grid(grid(igrid)%motherP)%yAxis(inY(1)+1) )/2.) &
                                        & inY(1) = inY(1)+1                                   
                                   call locate(grid(grid(igrid)%motherP)%zAxis, &
                                        & posVector%z,inZ(1))
                                   if (posVector%z > (grid(grid(igrid)%motherP)%zAxis(inZ(1))+&
                                        & grid(grid(igrid)%motherP)%zAxis(inZ(1)+1) )/2.) &
                                        & inZ(1) = inZ(1)+1                                   
                                end if

                                call energyPacketRun(chTypeD,posVector,inX,inY,inZ,igrid)

                             end do
                          end if
                       end if

                    end do
                 end do
              end do

           end do

           print*, "! energyPacketDriver: ending resonance line packets transfer"

        end if


        if (iStar>0) print*, 'Qphot = ', Qphot

        ! evaluate Jste and Jdif
        ! NOTE : deltaE is in units of [E36 erg/s] however we also need a factor of
        ! 1.e-45 from the calculations of the volume of the cell hence these
        ! two factors cancel each other out giving units of [E-9erg/s] so we need to
        ! multiply by 1.E-9
        ! NOTE : Jste and Jdif calculated this way are in units of
        ! [erg sec^-1 cm^-2] -> no Hz^-1 as they are summed over separate bins (see
        ! Lucy A&A (1999)                                                                                                                                   

        if(iStar>0.) then
           print*, 'Lstar', Lstar(iStar)           
        end if


        contains

        recursive subroutine energyPacketRun(chType, position, xP, yP, zP, gP)
            implicit none

            character(len=7), intent(in)     :: chType           ! stellar or diffuse?

            integer, optional, dimension(2), intent(in)    :: xP, yP, &
                 & zP                                            ! cartesian axes indeces 
                                                                 ! 1= mother; 2=sub

            
            integer, optional, intent(inout) :: gP               ! grid index
            integer                          :: igpr             ! grid pointer 1= mother 2=sub
            integer                          :: difSourceL(3)    ! cell indeces

            type(vector),intent(in), optional:: position         ! the position of the photon
        
            ! local variables

            type(photon_packet)              :: enPacket         ! the energu packet

            integer                          :: err              ! allocation error status
            integer                          :: i, j             ! counters  
            integer                          :: idirP, idirT     ! direction cosines

            real :: number 
            real, save :: ionPhot = 0.       

            if (present(gP)) then
               if (gP==1) then
                  igpr = 1
               else if (gP>1) then
                  igpr = 2
               else
                  print*,  "! energyPacketRun: insane grid index"
                  stop
               end if
            else 
               igpr=1
            end if

            ! create a new photon packet
            select case (chType)

            ! if the energy packet is stellar
            case ("stellar")
                ! check for errors in the sources position
                if (present(position) ) then
                    if( position /= starPosition(iStar) ) then
                        print*, "! energyPacketRun: stellar energy packet must&
                             & start at the stellar position"
                        stop
                    end if
                end if

                ! create the packet        
                enPacket = newPhotonPacket(chType)

            ! if the photon is from an extra source of diffuse radiation
             case ("diffExt")

                ! check that the grid and cell have been specified
                if (.not.(present(gp).and.present(xP).and.present(yP).and.present(zP))) then
                    print*, "! energyPacketRun: gp and xp,yp and zp must be specified if iStar=0"
                    stop
                end if

                difSourceL(1) = xP(igpr)
                difSourceL(2) = yP(igpr)
                difSourceL(3) = zP(igpr)

                
                ! create the packet        
                if (.not.present(gP)) gP=1

                enPacket = newPhotonPacket(chType=chType, gP=gP, difSource=difSourceL)

            ! if the photon is diffuse

            case ("diffuse")

                ! check that the position has been specified
                if (.not.present(position)) then
                    print*, "! energyPacketRun: position of the new diffuse&
                         & energy packet has not been specified"
                    stop
                end if

                ! check also that axes indeces have been carried through (save time)
                if (.not.(present(xP).and.present(yP).and.present(zP))) then
                    print*, "! energyPacketRun: cartesian axes indeces of the new diffuse &
                         & energy packet has not been specified"
                    stop
                end if
                ! check also that grid index have been carried through 
                if (.not.(present(gP))) then
                    print*, "! energyPacketRun: cartesian axes indeces of the new diffuse &
                         & energy packet has not been specified"
                    stop
                end if

                ! create the packet

                enPacket = newPhotonPacket(chType, position, xP, yP, zP, gP)

            case ("dustEmi")

                 ! check that the position has been specified
                if (.not.present(position)) then
                    print*, "! energyPacketRun: position of the new dust emitted &
                         & energy packet has not been specified"
                    stop
                end if

                ! check also that axes indeces have been carried through (save time)
                if (.not.(present(xP).and.present(yP).and.present(zP))) then
                    print*, "! energyPacketRun: cartesian axes indeces of the new dust emitted &
                         &energy packet has not been specified"
                    stop
                end if
                ! check also that grud index have been carried through
                if (.not.(present(gP))) then
                    print*, "! energyPacketRun: cartesian axes indeces of the new dust emitted &
                         &energy packet has not been specified"
                    stop
                end if

                ! crenPacketeate the packet
                enPacket = newPhotonPacket(chType=chType, position=position, xP=xP, yP=yP, zP=zP, gP=gP)

            end select 

            if (.not.lgDust .and. enPacket%nu < ionEdge(1) .and. .not.enPacket%lgLine) then

               ! the packet escapes without further interaction
               idirT = int(acos(enPacket%direction%z)/dTheta)+1
               if (idirT>totangleBinsTheta) then
                  idirT=totangleBinsTheta
               end if
               if (idirT<1 .or. idirT>totAngleBinsTheta) then
                  print*, '! energyPacketRun: error in theta direction cosine assignment',&
                       &  idirT, enPacket, dTheta, totAngleBinsTheta
                  stop
               end if
              

               if (enPacket%direction%x<1.e-35) then
                  idirP = 0
               else
                  idirP = int(atan(enPacket%direction%y/enPacket%direction%x)/dPhi)             
               end if
               if (idirP<0) idirP=totAngleBinsPhi+idirP
               idirP=idirP+1

               if (idirP>totangleBinsPhi) then
                  idirP=totangleBinsPhi
!                  print*, '! energyPacketRun: idir>totanglebins - error corrected', &
!                       & idir, totanglebins, enPacket%direction, dtheta
               end if
             
               if (idirP<1 .or. idirP>totAngleBinsPhi) then
                  print*, '! energyPacketRun: error in phi direction cosine assignment',&
                       &  idirP, enPacket, dPhi, totAngleBinsPhi
                  stop
               end if

               if (nAngleBins>0) then
                  if (viewPointPtheta(idirT) == viewPointPphi(idirP).or. &
                       & (viewPointTheta(viewPointPphi(idirP))==viewPointTheta(viewPointPtheta(idirT))) .or. & 
                       & (viewPointPhi(viewPointPtheta(idirT))==viewPointPhi(viewPointPphi(idirP))) ) then
                     grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), enPacket%nuP,viewPointPtheta(idirT)) = &
                          &grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                          & enPacket%nuP,viewPointPtheta(idirT)) + deltaE(iStar)
                     if (viewPointPtheta(idirT)/=0) grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), & 
                          & enPacket%nuP,0) = &
                          & grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                          & enPacket%nuP,0) +  deltaE(iStar)
                  else
                     grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), & 
                          & enPacket%nuP,0) = &
                          & grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                          & enPacket%nuP,0) +  deltaE(iStar)
                  end if
                              
               else

                  if (enPacket%origin(1) == 0) then 
                     print*, '! energyPacketRun: enPacket%origin(1) ==0'
                     stop
                  end if
                  if (enPacket%origin(2) < 0) then 
                     print*, '! energyPacketRun: enPacket%origin(2) < 0'
                     stop
                  end if

                  grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), & 
                       & enPacket%nuP,0) = &
                       & grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                       & enPacket%nuP,0) +  deltaE(iStar)
                  
               end if

               return
            end if

            ! if the new packet is capable of re-ionizing or we have dust
            if (.not.enPacket%lgLine) then

                ! compute the next segment of trajectory
                call pathSegment(enPacket)

                return

            else ! if the packet is a line packet 
                ! add to respective line packet bin

               if (lgDebug) &
                    & grid(gP)%linePackets(grid(gP)%active(enPacket%xP(igpr), &
                    & enPacket%yP(igpr), enPacket%zP(igpr)), enPacket%nuP) = &
                    & grid(gP)%linePackets(grid(gP)%active(enPacket%xP(igpr), &
                    & enPacket%yP(igpr), enPacket%zP(igpr)), enPacket%nuP) + deltaE(iStar)


            end if

        end subroutine energyPacketRun

        ! this function initializes a photon packet
        function initPhotonPacket(nuP,  position, lgLine, lgStellar, xP, yP, zP, gP)
            implicit none

            type(photon_packet)      :: initPhotonPacket  ! the photon packet
   
            real                     :: random            ! random number

            integer, intent(in)      :: nuP               ! the frequency of the photon packet
            integer, intent(in),dimension(2) :: xP, yP, &
                 & zP                                     ! indeces of position on the x, y and z axes            
            integer, intent(in)      :: gP                ! grid index
            integer                  :: igpi              ! grid pointer 1=mother, 2=sub


            logical, intent(in)      :: lgLine, lgStellar ! line, stellar packet?

            type(vector), intent(in) :: position          ! the position at which the photon
                                                          ! packet is created    
            ! local variables

            integer                  :: i, irepeat        ! counter


            initPhotonPacket%position = position

            initPhotonPacket%iG  = gP
            
            if (gP==1) then
               igpi=1 
            else if (gp>1) then
               igpi=2
            else
               print*, "! initPhotonPacket: insane gridp pointer"
               stop
            end if
           
            initPhotonPacket%nuP      = nuP       
           
            initPhotonPacket%lgStellar = lgStellar

            ! check if photon packen is line or continuum photon
            if ( lgLine ) then
                ! line photon
                initPhotonPacket%nu       = 0.
                initPhotonPacket%lgLine   = .true.
            else
                ! continuum photon
                initPhotonPacket%nu       = nuArray(nuP)
                initPhotonPacket%lgLine   = .false.          
            end if

            initPhotonPacket%xP  = xP
            initPhotonPacket%yP  = yP
            initPhotonPacket%zP  = zP


            ! cater for plane parallel ionization case
            if (initPhotonPacket%lgStellar .and. lgPlaneIonization) then
               
               ! get position
               
               ! x-direction
               call random_number(random)
               random = 1. - random
               initPhotonPacket%position%x = &
                    & -(grid(gP)%xAxis(2)-grid(gP)%xAxis(1))/2. + random*( &
                    & (grid(gP)%xAxis(2)-grid(gP)%xAxis(1))/2.+&
                    & (grid(gP)%xAxis(grid(gP)%nx)-grid(gP)%xAxis(grid(gP)%nx-1))/2.+&
                    & grid(gP)%xAxis(grid(gP)%nx))
               if (initPhotonPacket%position%x<grid(gP)%xAxis(1)) &
                    & initPhotonPacket%position%x=grid(gP)%xAxis(1)
               if (initPhotonPacket%position%x>grid(gP)%xAxis(grid(gP)%nx)) & 
                    initPhotonPacket%position%x=grid(gP)%xAxis(grid(gP)%nx)

               call locate(grid(gP)%xAxis, initPhotonPacket%position%x, initPhotonPacket%xP(igpi))
               if (initPhotonPacket%xP(igpi) < grid(gP)%nx) then
                  if (initPhotonPacket%position%x >= (grid(gP)%xAxis(initPhotonPacket%xP(igpi))+&
                       & grid(gP)%xAxis(initPhotonPacket%xP(igpi)+1))/2.) &
                       & initPhotonPacket%xP(igpi) = initPhotonPacket%xP(igpi)+1
               end if

               ! y-direction
               initPhotonPacket%position%y = 0.
               initPhotonPacket%yP(igpi) = 1

               ! z-direction
               call random_number(random)
               random = 1. - random
               initPhotonPacket%position%z = -(grid(gP)%zAxis(2)-grid(gP)%zAxis(1))/2. + random*( &
                    & (grid(gP)%zAxis(2)-grid(gP)%zAxis(1))/2.+&
                    & (grid(gP)%zAxis(grid(gP)%nz)-grid(gP)%zAxis(grid(gP)%nz-1))/2.+&
                    & grid(gP)%zAxis(grid(gP)%nz))
               if (initPhotonPacket%position%z<grid(gP)%zAxis(1)) & 
                    & initPhotonPacket%position%z=grid(gP)%zAxis(1)
               if (initPhotonPacket%position%z>grid(gP)%zAxis(grid(gP)%nz)) & 
                    & initPhotonPacket%position%z=grid(gP)%zAxis(grid(gP)%nz)

              call locate(grid(gP)%zAxis, initPhotonPacket%position%z, initPhotonPacket%zP(igpi))
               if (initPhotonPacket%zP(igpi) < grid(gP)%nz) then               
                  if (initPhotonPacket%position%z >= (grid(gP)%xAxis(initPhotonPacket%zP(igpi))+&
                       & grid(gP)%zAxis(initPhotonPacket%zP(igpi)+1))/2.) initPhotonPacket%zP(igpi) =& 
                       & initPhotonPacket%zP(igpi)+1
               end if

               if (initPhotonPacket%xP(igpi)<1) initPhotonPacket%xP(igpi)=1             
               if (initPhotonPacket%zP(igpi)<1) initPhotonPacket%zP(igpi)=1

               ! direction is parallel to y-axis direction
               initPhotonPacket%direction%x = 0.
               initPhotonPacket%direction%y = 1.
               initPhotonPacket%direction%z = 0.

               if (initPhotonPacket%xP(igpi) >  grid(gP)%xAxis(grid(gP)%nx) .or. &
                    & initPhotonPacket%zP(igpi) >  grid(gP)%zAxis(grid(gP)%nz)) then
                  print*, "! initPhotonPacket: insanity in planeIonisation init"
                  print*, igpi, initPhotonPacket%xP(igpi),  grid(gP)%xAxis(grid(gP)%nx), &
                       & initPhotonPacket%zP(igpi), grid(gP)%zAxis(grid(gP)%nz),  random, initPhotonPacket%position%z

                  stop
               end if

                planeIonDistribution(initPhotonPacket%xP(igpi),initPhotonPacket%zP(igpi)) = &
                     & planeIonDistribution(initPhotonPacket%xP(igpi),initPhotonPacket%zP(igpi)) + 1

             else

                do irepeat = 1, 1000000
                   ! get a random direction
                   initPhotonPacket%direction = randomUnitVector()
                   if (initPhotonPacket%direction%x/=0. .and. & 
                        & initPhotonPacket%direction%y/=0. .and. & 
                        & initPhotonPacket%direction%z/=0.) exit
                end do
            end if

            if ((lgSymmetricXYZ) .and. initPhotonPacket%lgStellar .and. .not.lgMultistars) then
                if (initPhotonPacket%direction%x<0.) &
                     & initPhotonPacket%direction%x = -initPhotonPacket%direction%x
                if (initPhotonPacket%direction%y<0.) &
                     & initPhotonPacket%direction%y = -initPhotonPacket%direction%y
                if (initPhotonPacket%direction%z<0.) &
                     & initPhotonPacket%direction%z = -initPhotonPacket%direction%z
            end if

            initPhotonPacket%origin(1) = gP
            initPhotonPacket%origin(2) = grid(gP)%active(initPhotonPacket%xP(igpi),&
                 & initPhotonPacket%yP(igpi), initPhotonPacket%zP(igpi))                           
            

        end function initPhotonPacket

    
        ! this subroutine determines the frequency of a newly created photon packet
        ! according to the given probability density
        subroutine getNu(probDen, nuP)

            real, dimension(:), intent(in) :: probDen    ! probability density function
       
            integer, intent(out)           :: nuP         ! frequency index of the new

            ! local variables
            real                           :: random     ! random number

            ! get a random number
            call random_number(random)

            random = 1.-random

            ! see what frequency random corresponds to 
            call locate(probDen, random, nuP)
             if (nuP <= 0) nuP = 1

 !           if (probDen(nuP) /= random) then
 !              nuP = nuP+1               
 !           end if

             if (nuP<nbins) then
                if (random>=(probDen(nuP+1)+probDen(nuP))/2.) nuP=nuP+1
             end if

        end subroutine getNu

        ! this subroutine determines the frequency of a newly created photon packet
        ! according to the given probability density
        ! does not use bisection to locate nu on array
        subroutine getNu2(probDen, nuP)

            real, dimension(:), intent(in) :: probDen    ! probability density function

            real                           :: random     ! random number
       
            integer, intent(out)           :: nuP        ! frequency index of the new

            integer                        :: isearch,i  !  

            ! get a random number
            call random_number(random)
            
            do i = 1, 10000
               if (random==0 .or. random==1.) then
                  call random_number(random)
               else
                  exit
               end if
            end do
            if (i>=10000) then
               print*, '! getNu2: problem with random number generator', random, i
               stop
            end if

            ! see what frequency random corresponds to 
            nuP=1
            do isearch = 1, nbins
               if (random>=probDen(isearch)) then
                  nuP=isearch
               else 
                  exit                  
               end if
            end do            

            if (nuP<nbins) then
               nuP=nuP+1
            end if

            if (nuP>=nbins) then
               print*, 'random: ', random
               print*, 'probDen: ', probDen
            end if

          end subroutine getNu2

        
        ! this function creates a new photon packet
        function newPhotonPacket(chType, position, xP, yP, zP, gP, difSource)
    
            type(photon_packet)                :: newPhotonPacket! the photon packet to be created

            character(len=7), intent(in)       :: chType         ! stellar or diffuse?

            type(vector), intent(in), optional :: position       ! the position of the photon
                                                                 ! packet
            ! local variables
            type(vector)                       :: positionLoc    ! the position of the photon
                                                                 ! packet

            integer                            :: nuP            ! the frequency index of the photon packet
            integer, dimension(2)         :: orX,orY,orZ    ! dummy
            integer, optional, dimension(2),intent(in) :: xP, yP, & 
                 & zP                                            ! cartesian axes indeces    
            integer, optional, intent(in)      :: difSource(3)  ! grid and cell indeces
            integer, optional, intent(inout)   :: gP
            integer                            :: igpn           ! grid pointe 1=motehr, 2=sub
            logical                            :: lgLine_loc=.false.! line photon?

            real                               :: random         ! random number

            if (present(gP)) then
               if (gP==1) then
                  igpn = 1
               else if (gp>1) then
                  igpn = 2
               else
                  print*,  "! newPhotonPacket: insane grid pointer"
                  stop
               end if
            else 
               igpn = 1
            end if

            select case (chType)

            ! if the photon is stellar
            case ("stellar")

                ! check for errors in the sources position
                if (present(position) ) then
                    if( position /= starPosition(iStar) ) then
                        print*, "! newPhotonPacket: stellar photon packet must&
                             & start at the stellar position"
                        stop
                    end if
                end if 

!                gP = starIndeces(iStar,4)

                if (starIndeces(iStar,4) == 1) then
                   igpn = 1
                else if (starIndeces(iStar,4) > 1) then
                   igpn = 2
                else
                   print*,  "! newPhotonPacket: insane grid pointer -star position- "
                   stop
                end if

                ! determine the frequency of the newly created photon packet
                call getNu2(inSpectrumProbDen(iStar,1:nbins), nuP)

                if (nuP>=nbins) then
                   print*, "! newPhotonPacket: insanity occured in stellar photon &
                        &nuP assignment (nuP,xP,yP,zP,activeP)", nuP, xP(igpn),yP(igpn),zP(igpn), &
                        & grid(starIndeces(iStar,4))%active(xP(igpn),yP(igpn),zP(igpn))
                   print*, "inSpectrumProbDen: ",iStar,inSpectrumProbDen(iStar,:), nuP
                   stop
                end if
                
                if (nuP < 1) then
                    print*, "! newPhotonPacket: insanity occured in stellar photon &
&                               nuP assignment"
                    stop
                end if

                ! initialize the new photon packet
                orX(igpn) = starIndeces(iStar,1)
                orY(igpn) = starIndeces(iStar,2)
                orZ(igpn) = starIndeces(iStar,3)

!                if (present(gP)) then
                   if (grid(starIndeces(iStar,4))%active(orX(igpn), orY(igpn), orZ(igpn)) < 0.) then
                      print*, "! newPhotonPacket: new packet cannot be emitted from re-mapped cell -1-" 
                      print*, "chType, nuP, starPosition(iStar), .false., .true., orX,orY,orZ, gp"
                      print*, chType, nuP, starPosition(iStar), .false., .true., orX,orY,orZ, gp
                      stop
                   end if

                   newPhotonPacket = initPhotonPacket(nuP, starPosition(iStar), .false., .true., orX,orY,orZ, starIndeces(iStar,4))

!                else
!                   if (grid(1)%active(orX(igpn), orY(igpn), orZ(igpn)) < 0.) then
!                      print*, "! newPhotonPacket: new packet cannot be emitted from re-mapped cell -2- "
!                      print*, "chType, nuP, starPosition(iStar), .false., .true., orX,orY,orZ, gp"
!                      print*, chType, nuP, starPosition(iStar), .false., .true., orX,orY,orZ, '1'
!                      stop
!                   end if
!                   newPhotonPacket = initPhotonPacket(nuP, starPosition(iStar), .false., .true., orX,orY,orZ, 1)
!                end if
                if (newPhotonPacket%nu>1.) then
                   Qphot = Qphot + deltaE(iStar)/(2.1799153e-11*newPhotonPacket%nu)
                end if

                ! if the photon is from an extra diffuse source
             case ("diffExt")

                ! check that the grid and cell indeces have been specified
                if (.not.(present(gp).and.present(difSource))) then
                    print*, "! newPhotonPacket: grid and cell indeces of the new extra diffuse &
                         & photon packet have not been specified"
                    stop
                end if

                call getNu2(inSpectrumProbDen(0,1:nbins), nuP)

                if (nuP>=nbins) then
                   print*, "! newPhotonPacket: insanity occured in extra diffuse photon &
                        & nuP assignment (nuP,gp,activeP)", nuP, gp
                   print*, "difSpectrumProbDen: ", inSpectrumProbDen(0,:)
                   stop
                end if

                if (nuP < 1) then
                   print*, "! newPhotonPacket: insanity occured in extra diffuse photon &
                        & nuP assignment (nuP,gp,activeP)", nuP, gp,grid(gP)%active(xP(igpn),yP(igpn),zP(igpn))
                   print*, "difSpectrumProbDen: ", inSpectrumProbDen(0,:)
                   stop
                end if

                positionLoc%x = grid(gP)%xAxis(difSource(1))
                positionLoc%y = grid(gP)%yAxis(difSource(2))
                positionLoc%z = grid(gP)%zAxis(difSource(3))

                ! initialize the new photon packet
                orX(igPn) = difSource(1)
                orY(igPn) = difSource(2)
                orZ(igPn) = difSource(3)

                ! initialize the new photon packet
                if (grid(gP)%active(orX(igpn), orY(igpn), orZ(igpn)) < 0.) then
                   print*, "! newPhotonPacket: new packet cannot be emitted from re-mapped cell -3-"
                   print*, "chType, nuP, starPosition(iStar), .false., .true., orX,orY,orZ, gp"
                   print*, chType, nuP, starPosition(iStar), .false., .true., orX,orY,orZ, gp
                   stop
                end if
                newPhotonPacket = initPhotonPacket(nuP, positionLoc, .false., .false., orX,&
                     & orY, orZ, gP)

            ! if the photon is diffuse
            case ("diffuse")

                ! check that gas is present in the grid
                if (.not.lgGas) then
                   print*, "! newPhotonPacket: diffuse packet cannot be created in a no gas grid"
                   stop
                end if

                ! check that the position has been specified
                if (.not.present(position)) then
                    print*, "! newPhotonPacket: position of the new diffuse &
                         & photon packet has not been specified"
                    stop
                end if
            
                ! check that the position indeces have been specified
                if (.not.(present(xP).and.present(yP).and.present(zP))) then
                    print*, "! newPhotonPacket: position indeces of the new diffuse &
                         & photon packet have not been specified"
                    stop
                end if
                ! check that the grid indeces have been specified
                if (.not.(present(gP))) then
                    print*, "! newPhotonPacket: grid index of the new diffuse &
                         & photon packet has not been specified"
                    stop
                end if
 
                ! check that the position is not inside the inner region
                if (grid(gP)%active(xP(igPn),yP(igPn),zP(igPn))<= 0) then                   
                    print*, "! newPhotonPacket: position of the new diffuse &
                         & photon packet is inside the inner region", xP(igPn),yP(igPn),zP(igPn),gP
                    stop
                end if

                ! decide whether continuum or line photon
                call random_number(random)

                random = 1.-random

                if (random <= grid(gP)%totalLines(grid(gP)%active(xP(igPn),yP(igPn),zP(igPn)))) then 
                   ! line photon
                   ! line photons escape so don't care which one it is unless debugging
                   if (lgDebug) then
                      call getNu2( grid(gP)%linePDF(grid(gP)%active(xP(igPn),yP(igPn),zP(igPn)),:), nuP )

                      if (nuP < 1) then
                         print*, "! newPhotonPacket: insanity occured in line photon &
                              & nuP assignment"
                         stop
                      end if
                           
                   else
                      
                      nuP = 0

                   end if

                   ! initialize the new photon packet
                   if (grid(gP)%active(xP(igpn), yp(igpn), zp(igpn)) < 0.) then
                      print*, "! newPhotonPacket: new packet cannot be emitted from re-mapped cell -4-"
                      print*, "chType, nuP, starPosition(iStar), .false., .true., xp,yp,zp, gp"
                      print*, chType, nuP, starPosition(iStar), .false., .true., xp,yp,zp, gp
                      stop
                   end if

                   newPhotonPacket = initPhotonPacket(nuP, position, .true., .false., xP, yP, zP, gP)
                else 
                    ! continuum photon

                    call getNu2(grid(gP)%recPDF(grid(gP)%active(xP(igPn),yP(igPn),zP(igPn)),1:nbins), nuP)

                    if (nuP>=nbins) then
                       print*, "! newPhotonPacket: insanity occured in diffuse photon &
                       & nuP assignment (nuP,xP,yP,zP,activeP)", nuP, xP(igPn),yP(igPn),zP(igPn),&
                       &  grid(gP)%active(xP(igPn),yP(igPn),zP(igPn))
                       print*, "recPDF: ", grid(gP)%recPDF(grid(gP)%active(xP(igPn),yP(igPn),zP(igPn)),1:nbins)
                       stop
                    end if

                    if (nuP < 1) then
                        print*, "! newPhotonPacket: insanity occured in diffuse photon &
                             & nuP assignment", nuP, xP(igPn),yP(igPn),zP(igPn), & 
                             & grid(gP)%active(xP(igPn),yP(igPn),zP(igPn))
                       print*, "recPDF: ", grid(gP)%recPDF(grid(gP)%active(xP(igPn),yP(igPn),zP(igPn)),:)
                        stop
                    end if

                    ! initialize the new photon packet
                   if (grid(gP)%active(xP(igpn), yp(igpn), zp(igpn)) < 0.) then
                      print*, "! newPhotonPacket: new packet cannot be emitted from re-mapped cell -5-"
                      print*, "chType, nuP, starPosition(iStar), .false., .true., xp,yp,zp, gp"
                      print*, chType, nuP, starPosition(iStar), .false., .true., xp,yp,zp, gp
                      stop
                   end if

                    newPhotonPacket = initPhotonPacket(nuP, position, .false., .false., xP, yP, zP, gP)
                end if

            case ("dustEmi")

               ! check dust is present
               if (.not.lgDust) then
                  print*, "! newPhotonPacket: dust emitted packet cannot be created in a &
                       &no dust grid."
                  stop
               end if

               if (lgGas) then
                  print*, "! newPhotonPacket: dustEmi-type packet should be created in a &
                       & grid containing gas."
                  stop
               end if

               ! check that the position has been specified
               if (.not.present(position)) then
                  print*, "! newPhotonPacket: position of the new dust emitted &
                       &photon packet has not been specified"
                  stop
               end if

               ! check that the position indeces have been specified
               if (.not.(present(xP).and.present(yP).and.present(zP))) then
                  print*, "! newPhotonPacket: position indeces of the new dust emitted &
                       &photon packet have not been specified"
                  stop
               end if
               ! check that the position indeces have been specified
               if (.not.(present(gP))) then
                  print*, "! newPhotonPacket: grid index of the new dust emitted &
                       &photon packet has not been specified"
                  stop
               end if

               ! check that the position is not inside the inner region
               if (grid(gP)%active(xP(igPn),yP(igPn),zP(igPn))<= 0) then
                  print*, "! newPhotonPacket: position of the new dust emitted &
                       &photon packet is inside the inner region", xP(igPn),yP(igPn),zP(igPn)
                  stop
               end if

               call getNu2(grid(gP)%dustPDF(grid(gP)%active(xP(igPn),yP(igPn),zP(igPn)),1:nbins), nuP)

               if (nuP>=nbins) then
                   print*, "! newPhotonPacket: insanity occured in dust emitted photon &
                       &nuP assignment (iphot, nuP,xP(gP),yP(gP),zP(gP),activeP)", iphot, &
                       & nuP, xP(igPn),yP(igPn),zP(igPn), &
                       & grid(gP)%active(xP(igPn),yP(igPn),zP(igPn))
                   print*, "dustPDF: ", grid(gP)%dustPDF(grid(gP)%active(xP(igPn),yP(igPn),zP(igPn)),1:nbins)
                   print*, "grain T: ", grid(gP)%Tdust(:,0,grid(gP)%active(xP(igPn),yP(igPn),zP(igPn)))
                   stop
                end if

               if (nuP < 1) then
                  print*, "! newPhotonPacket: insanity occured in dust emitted photon &
                       &nuP assignment", nuP,xP(igPn),yP(igPn),zP(igPn), grid(gP)%active(xP(igPn),yP(igPn),zP(igPn))
                  print*, "dustPDF: ", grid(gP)%dustPDF(grid(gP)%active(xP(igPn),yP(igPn),zP(igPn)),1:nbins)
                  print*, "grain T: ", grid(gP)%Tdust(:, 0, grid(gP)%active(xP(igPn),yP(igPn),zP(igPn)))
                  stop
               end if

               ! initialize the new photon packet
                   if (grid(gP)%active(xP(igpn), yp(igpn), zp(igpn)) < 0.) then
                      print*, "! newPhotonPacket: new packet cannot be emitted from re-mapped cell -6-"
                      print*, "chType, nuP, starPosition(iStar), .false., .true., xp,yp,zp, gp"
                      print*, chType, nuP, starPosition(iStar), .false., .true., xp,yp,zp, gp
                      stop
                   end if

               newPhotonPacket = initPhotonPacket(nuP, position, .false., .false., xP, yP, zP, gP)

            ! if the photon packet type is wrong or missing
            case default
        
                print*, "! newPhotonPacket: wrong photon packet type - 'stellar', 'diffuse' and &
                     & dust emitted types allowed-"
                stop
            end select

        end function newPhotonPacket
            
        subroutine pathSegment(enPacket)
          implicit none

          type(photon_packet), intent(inout) :: enPacket ! the energy packet

          ! local variables
          type(vector)                    :: vHat     ! direction vector
          type(vector)                    :: rVec     ! position vector
          
          real                            :: absTau   ! optical depth
          real                            :: dlLoc    ! local displacement
          real                            :: dx, dy, dz 
          real                            :: dSx, dSy, dSz 
                                                      ! distances from x,y and z wall
          real                            :: dS       ! distance from nearest wall 
          real                            :: dV       ! lume of this cell
          real                            :: passProb ! prob of passing the next segment
          real                            :: probSca  ! prob that the packet scatters
          real                            :: radius   ! radius
          real                            :: random   ! random number
          real                            :: tauCell  ! local tau

          integer                         :: idirT,idirP ! direction cosine counters
          integer                         :: i, j, nS ! counter
          integer                         :: xP,yP,zP ! cartesian axes indeces
          integer                         :: gP       ! grid index
          integer                         :: igpp     ! grid index 1=mother 2=sub
          integer                         :: safeLimit =1000
                                                      ! safe limit for the loop

          character(len=7)                :: packetType ! stellar, diffuse, dustEmitted?

          logical                         :: lgScattered ! is the packet scattering with dust?
          logical                         :: lgReturn


          if (enPacket%iG == 1) then
             igpp = 1
          else if (enPacket%iG>1) then
             igpp = 2
          else 
             print*, "! pathSegment: insane grid index"
             stop
          end if

          ! check that the input position is not outside the grid
          if ( (enPacket%iG <= 0).or.(enPacket%iG > nGrids) ) then   
             print*, "! pathSegment: starting position not in any defined gridhses",&
                  & enPacket
             stop
          else if ( (enPacket%xP(igpp) <= 0).or.&
               &(enPacket%xP(igpp) > grid(enPacket%iG)%nx) ) then
             print*, "! pathSegment: starting position in x is outside the grid",&
                  & enPacket
             stop
          else if ( (enPacket%yP(igpp) <= 0).or. & 
               & (enPacket%yP(igpp) > grid(enPacket%iG)%ny) ) then
             print*, "! pathSegment: starting position in y is outside the grid",&
                  & enPacket
             stop
          else if ( (enPacket%zP(igpp) <= 0).or.& 
               & (enPacket%zP(igpp) > grid(enPacket%iG)%nz) ) then   
             print*, "! pathSegment: starting position in z is outside the grid",&
                  & enPacket
             stop          
          end if

          ! define vHat and rVec
          rVec = enPacket%position
          vHat = enPacket%direction

          ! initialize xP, yP,zP
          xP = enPacket%xP(igpp)
          yP = enPacket%yP(igpp)
          zP = enPacket%zP(igpp) 
          gP = enPacket%iG

          ! initialise distance from walls
          dSx = 0.
          dSy = 0.
          dSz = 0.

          if (lg1D) then
             radius = 1.e10*sqrt((rVec%x/1.e10)*(rVec%x/1.e10) + &
                  &                               (rVec%y/1.e10)*(rVec%y/1.e10) + &
                  &                               (rVec%z/1.e10)*(rVec%z/1.e10))
             call locate(grid(1)%xAxis, radius, xP)
             if (nGrids > 1 .or. gP >1) then
                print*, " ! energyPacketRun: multiple grids are not allowed in a 1D simulation"
                stop
             end if
          end if

          ! initialize optical depth
          absTau = 0.

          ! get a random number
          call random_number(random)
                          
          ! calculate the probability 
          passProb = -log(1.-random)

          ! speed up photons that my be trapped
          if (lgPlaneIonization) then
             safeLimit=5000
          else
!             safeLimit=500000
             safeLimit=1000
          end if

          do i = 1, safeLimit

             do j = 1, safeLimit

                if (xP > grid(gP)%nx .or. xP < 1 .or. &
                     & yP > grid(gP)%ny .or. yP < 1 .or. &
                     & zP > grid(gP)%nz .or. zP < 1 ) then
                   print*, "! pathSegment: insanity [gp,xp,yp,zp,j,i]", & 
                        & gp, xp, yp, zp, j, i
                   stop
                end if

                if (grid(gP)%active(xP,yP,zP)<0) then                

                   ! packet is entering a subgrid
                   enPacket%xP(1) = xP
                   enPacket%yP(1) = yP
                   enPacket%zP(1) = zP
                   
                   gP = abs(grid(gP)%active(xP,yP,zP))

                   ! where is the packet in the sub-grid?

                   call locate(grid(gP)%xAxis, rVec%x, xP)
                   if (xP==0) xP = xP+1
                   if (xP< grid(gP)%nx) then
                      if (rVec%x >  (grid(gP)%xAxis(xP+1)+grid(gP)%xAxis(xP))/2.) &
                           & xP = xP + 1
                   end if

                   call locate(grid(gP)%yAxis, rVec%y, yP)
                   if (yP==0) yP=yP+1
                   if (yP< grid(gP)%ny) then
                      if (rVec%y >  (grid(gP)%yAxis(yP+1)+grid(gP)%yAxis(yP))/2.) &
                           & yP = yP + 1
                   end if

                   call locate(grid(gP)%zAxis, rVec%z, zP)
                   if (zP==0) zP=zP+1
                   if (zP< grid(gP)%nz) then
                      if (rVec%z >  (grid(gP)%zAxis(zP+1)+grid(gP)%zAxis(zP))/2.) &
                           & zP = zP + 1
                   end if
                   
                end if

                enPacket%iG = gP
                igpp = 2

                ! find distances from all walls

                if (lgSymmetricXYZ) then
                   if ( rVec%x <= grid(1)%xAxis(1) ) then
                      if (vHat%x<0.) vHat%x = -vHat%x
                      rVec%x = grid(1)%xAxis(1)
                   end if
                   if ( rVec%y <= grid(1)%yAxis(1) ) then
                      if (vHat%y<0.) vHat%y = -vHat%y
                      rVec%y = grid(1)%yAxis(1)
                   end if
                   if ( rVec%z <= grid(1)%zAxis(1) ) then
                      if (vHat%z<0.) vHat%z = -vHat%z
                      rVec%z = grid(1)%zAxis(1)
                   end if
                end if

                if (vHat%x>0.) then
                   if (xP<grid(gP)%nx) then

                      dSx = ( (grid(gP)%xAxis(xP+1)+grid(gP)%xAxis(xP))/2.-rVec%x)/vHat%x

                      if (abs(dSx)<1.e-10) then
                         rVec%x=(grid(gP)%xAxis(xP+1)+grid(gP)%xAxis(xP))/2.
                         xP = xP+1
                      end if
                   else
                      dSx = ( grid(gP)%xAxis(grid(gP)%nx)-rVec%x)/vHat%x
                      if (abs(dSx)<1.e-10) then
                         rVec%x=grid(gP)%xAxis(grid(gP)%nx)
                         if (.not.lgPlaneIonization .and. gP==1) return
                      end if
                   end if
                else if (vHat%x<0.) then
                   if (xP>1) then
                      dSx = ( (grid(gP)%xAxis(xP)+grid(gP)%xAxis(xP-1))/2.-rVec%x)/vHat%x
                      if (abs(dSx)<1.e-10) then             
                         rVec%x=(grid(gP)%xAxis(xP)+grid(gP)%xAxis(xP-1))/2.
                         xP = xP-1
                      end if
                   else
                      dSx = (grid(gP)%xAxis(1)-rVec%x)/vHat%x
                      if (abs(dSx)<1.e-10) then             
                         rVec%x=grid(gP)%xAxis(1)
                      end if
                   end if
                else if (vHat%x==0.) then
                   dSx = grid(gP)%xAxis(grid(gP)%nx)
                end if
                
                if (.not.lg1D) then 
                   if (vHat%y>0.) then
                      if (yP<grid(gP)%ny) then
                         dSy = ( (grid(gP)%yAxis(yP+1)+grid(gP)%yAxis(yP))/2.-rVec%y)/vHat%y
                         if (abs(dSy)<1.e-10) then
                            rVec%y=(grid(gP)%yAxis(yP+1)+grid(gP)%yAxis(yP))/2.
                            yP = yP+1
                         end if
                      else
                         dSy = (  grid(gP)%yAxis(grid(gP)%ny)-rVec%y)/vHat%y
                         if (abs(dSy)<1.e-10) then
                            rVec%y=grid(gP)%yAxis(grid(gP)%ny)
                            if(gP==1) return
                         end if
                      end if
                   else if (vHat%y<0.) then
                      if (yP>1) then
                         dSy = ( (grid(gP)%yAxis(yP)+grid(gP)%yAxis(yP-1))/2.-rVec%y)/vHat%y
                         if (abs(dSy)<1.e-10) then             
                            rVec%y=(grid(gP)%yAxis(yP)+grid(gP)%yAxis(yP-1))/2.
                            yP = yP-1
                         end if
                      else 
                         dSy = ( grid(gP)%yAxis(1)-rVec%y)/vHat%y
                         if (abs(dSy)<1.e-10) then             
                            rVec%y=grid(gP)%yAxis(1)
                         end if
                      end if
                   else if (vHat%y==0.) then
                      dSy = grid(gP)%yAxis(grid(gP)%ny)
                   end if

                   if (vHat%z>0.) then
                      if (zP<grid(gP)%nz) then
                         dSz = ( (grid(gP)%zAxis(zP+1)+grid(gP)%zAxis(zP))/2.-rVec%z)/vHat%z
                         if (abs(dSz)<1.e-10) then
                            rVec%z=(grid(gP)%zAxis(zP+1)+grid(gP)%zAxis(zP))/2.
                            zP = zP+1
                         end if
                      else
                         dSz = ( grid(gP)%zAxis(grid(gP)%nz)-rVec%z)/vHat%z
                         if (abs(dSz)<1.e-10) then
                            rVec%z=grid(gP)%zAxis(grid(gP)%nz)
                            if (.not.lgPlaneIonization .and. gP==1) return
                         end if
                      end if
                   else if (vHat%z<0.) then
                      if (zP>1) then             
                         dSz = ( (grid(gP)%zAxis(zP)+grid(gP)%zAxis(zP-1))/2.-rVec%z)/vHat%z
                         if (abs(dSz)<1.e-10) then             
                            rVec%z=(grid(gP)%zAxis(zP)+grid(gP)%zAxis(zP-1))/2.
                            zP = zP-1
                         end if
                      else
                         dSz = ( grid(gP)%zAxis(1)-rVec%z)/vHat%z
                         if (abs(dSz)<1.e-10) then             
                            rVec%z=grid(gP)%zAxis(1)
                         end if
                      end if
                   else if (vHat%z==0.) then
                      dSz = grid(gP)%zAxis(grid(gP)%nz)
                   end if
                   
                   if (xP > grid(gP)%nx .or. xP < 1 .or. &
                        & yP > grid(gP)%ny .or. yP < 1 .or. &
                        & zP > grid(gP)%nz .or. zP < 1 ) then
                      print*, "! pathSegment: insanity -2- [gp,xp,yp,zp]", & 
                           & gp, xp, yp, zp
                      stop
                   end if

                end if
                 
                if (grid(gP)%active(xP,yP,zP)>=0) exit
             end do

             ! cater for cells on cell wall
             if ( abs(dSx)<1.e-10 ) dSx = grid(gP)%xAxis(grid(gP)%nx)
             if ( abs(dSy)<1.e-10 ) dSy = grid(gP)%yAxis(grid(gP)%ny)
             if ( abs(dSz)<1.e-10 ) dSz = grid(gP)%zAxis(grid(gP)%nz)

             ! find the nearest wall
             dSx = abs(dSx)
             dSy = abs(dSy)
             dSz = abs(dSz)

             if (dSx<=0.) then
                print*, '! pathSegment: [warning] dSx <= 0.',dSx
                print*, 'grid(gP)%xAxis ', grid(gP)%xAxis
                print*, 'gP,xP,grid(gP)%xAxis(xP), rVec%x, vHat%x'
                print*, gP,xP,grid(gP)%xAxis(xP), rVec%x, vHat%x
                dS = amin1(dSy, dSz)
             else if (dSy<=0.) then
                print*, '! pathSegment: [warning] dSy <= 0.', dSy
                print*, 'grid(gP)%yAxis ', grid(gP)%yAxis
                print*, 'gP,yP,grid(gP)%yAxis(yP), rVec%y, vHat%y'
                print*, gP,yP,grid(gP)%yAxis(yP), rVec%y, vHat%y
                dS = amin1(dSx, dSz)
             else if (dSz<=0.) then
                print*, '! pathSegment: [warning] dSz <= 0.', dSz
                print*, 'grid(gP)%zAxis ', grid(gP)%zAxis
                print*, 'gP,zP,grid(gP)%zAxis(zP), rVec%z, vHat%z'
                print*, gP,zP,grid(gP)%zAxis(zP), rVec%z, vHat%z
                dS = amin1(dSx, dSy)
             else
                dS = min(dSx,dSy)
                dS = min(dS, dSz)
             end if

             ! this should now never ever happen
             if (dS <= 0.) then
                print*, 'pathSegment: dS <= 0', dSx, dSy, dSz
                print*, gP, rVec
                stop
             end if

             ! calculate the optical depth to the next cell wall 
             tauCell = dS*grid(gP)%opacity(grid(gP)%active(xP,yP,zP), enPacket%nuP)


             ! find the volume of this cell
!             dV = getVolumeLoc(grid(gP), xP,yP,zP)


             if (lg1D) then
                if (nGrids>1) then
                   print*, '! getVolumeLoc: 1D option and multiple grids options are not compatible'
                   stop
                end if

                if (xP == 1) then              

                   dV = 4.*Pi* ( (grid(gP)%xAxis(xP+1)/1.e15)**3.)/3.


                else if ( xP==grid(gP)%nx) then
                   
                   dV = Pi* ( (3.*(grid(gP)%xAxis(xP)/1.e15)-(grid(gP)%xAxis(xP-1)/1.e15))**3. - &
                        & ((grid(gP)%xAxis(xP)/1.e15)+(grid(gP)%xAxis(xP-1)/1.e15))**3. ) / 6.

                else 

                   dV = Pi* ( ((grid(gP)%xAxis(xP+1)/1.e15)+(grid(gP)%xAxis(xP)/1.e15))**3. - &
                        & ((grid(gP)%xAxis(xP-1)/1.e15)+(grid(gP)%xAxis(xP)/1.e15))**3. ) / 6.

                end if

                dV = dV/8.

             else

                if ( (xP>1) .and. (xP<grid(gP)%nx) ) then

                   dx = abs(grid(gP)%xAxis(xP+1)-grid(gP)%xAxis(xP-1))/2.
                else if ( xP==1 ) then
                   if (lgSymmetricXYZ) then
                      dx = abs(grid(gP)%xAxis(xP+1)-grid(gP)%xAxis(xP))/2.
                   else 
                      dx = abs(grid(gP)%xAxis(xP+1)-grid(gP)%xAxis(xP))
                   end if
                else if ( xP==grid(gP)%nx ) then
                   dx = abs(grid(gP)%xAxis(xP)  -grid(gP)%xAxis(xP-1))
                end if

                if ( (yP>1) .and. (yP<grid(gP)%ny) ) then
                   dy = abs(grid(gP)%yAxis(yP+1)-grid(gP)%yAxis(yP-1))/2.
                else if ( yP==1 ) then
                   if (lgSymmetricXYZ) then
                      dy = abs(grid(gP)%yAxis(yP+1)-grid(gP)%yAxis(yP))/2.
                   else
                      dy = abs(grid(gP)%yAxis(yP+1)-grid(gP)%yAxis(yP))
                   end if
                else if ( yP==grid(gP)%ny ) then
                   dy = abs(grid(gP)%yAxis(yP)  -grid(gP)%yAxis(yP-1))
                end if

                if ( (zP>1) .and. (zP<grid(gP)%nz) ) then    
                   dz = abs(grid(gP)%zAxis(zP+1)-grid(gP)%zAxis(zP-1))/2.    
                 else if ( zP==1 ) then    
                   if (lgSymmetricXYZ) then
                      dz = abs(grid(gP)%zAxis(zP+1)-grid(gP)%zAxis(zP))/2.
                   else
                      dz = abs(grid(gP)%zAxis(zP+1)-grid(gP)%zAxis(zP))
                   end if
                else if ( zP==grid(gP)%nz ) then    
                   dz = abs(grid(gP)%zAxis(zP)-grid(gP)%zAxis(zP-1))
                end if

                dx = dx/1.e15
                dy = dy/1.e15
                dz = dz/1.e15      


                ! calculate the volume
                dV = dx*dy*dz

             end if

             ! check if the paintckets interacts within this cell
             if ((absTau+tauCell > passProb) .and. (grid(gP)%active(xP,yP,zP)>0)) then

                ! packet interacts
                
                ! calculate where within this cell the packet is absorbed
                dlLoc = (passProb-absTau)/grid(gP)%opacity(grid(gP)%active(xP,yP,zP), enPacket%nuP)

                ! update packet's position
                rVec = rVec + dlLoc*vHat

                if (lgSymmetricXYZ .and. gP==1) then
                   if ( rVec%x <= grid(gP)%xAxis(1) ) then
                      if (vHat%x<0.) vHat%x = -vHat%x
                      rVec%x = grid(gP)%xAxis(1)
                   end if
                   if ( rVec%y <= grid(gP)%yAxis(1) ) then
                      if (vHat%y<0.) vHat%y = -vHat%y
                      rVec%y = grid(gP)%yAxis(1)
                   end if
                   if ( rVec%z <= grid(gP)%zAxis(1) ) then
                      if (vHat%z<0.) vHat%z = -vHat%z
                      rVec%z = grid(gP)%zAxis(1)
                   end if
                end if

                ! add contribution of the packet to the radiation field
                if (enPacket%lgStellar) then
                   grid(gP)%Jste(grid(gP)%active(xP,yP,zP),enPacket%nuP) = &
                        grid(gP)%Jste(grid(gP)%active(xP,yP,zP),enPacket%nuP) + dlLoc*deltaE(iStar) / dV
                else ! if the energy packet is diffuse
                   if (lgDebug) then
                      grid(gP)%Jdif(grid(gP)%active(xP,yP,zP),enPacket%nuP) = &
                           & grid(gP)%Jdif(grid(gP)%active(xP,yP,zP),enPacket%nuP) + dlLoc*deltaE(iStar) / dV
                   else
                      grid(gP)%Jste(grid(gP)%active(xP,yP,zP),enPacket%nuP) = &
                           & grid(gP)%Jste(grid(gP)%active(xP,yP,zP),enPacket%nuP) + dlLoc*deltaE(iStar) / dV
                   end if
                end if                  

                ! check if the position within the cell is still within the outer radius
                if ( sqrt( (rvec%x/1.e10)**2. + (rvec%y/1.e10)**2. + (rvec%z/1.e10)**2.)*1.e10 >= R_out &
                     & .and. R_out > 0.) then
                   
                   ! the packet escapes without further interaction
                   
                   idirT = int(acos(enPacket%direction%z)/dTheta)+1
                   if (idirT>totangleBinsTheta) then
                      idirT=totangleBinsTheta
                   end if
                   if (idirT<1 .or. idirT>totAngleBinsTheta) then
                      print*, '! energyPacketRun: error in theta direction cosine assignment',&
                           &  idirT, enPacket, dTheta, totAngleBinsTheta
                      stop
                   end if

                   if (enPacket%direction%x<1.e-35) then
                      idirP = 0
                   else
                      idirP = int(atan(enPacket%direction%y/enPacket%direction%x)/dPhi)             
                   end if
                   if (idirP<0) idirP=totAngleBinsPhi+idirP
                   idirP=idirP+1
                   if (idirP>totangleBinsPhi) then
                      idirP=totangleBinsPhi
                   end if
                   
                   if (idirP<1 .or. idirP>totAngleBinsPhi) then
                      print*, '! energyPacketRun: error in Phi direction cosine assignment',&
                           &  idirP, enPacket, dPhi, totAngleBinsPhi
                      stop
                   end if
               
                   if (nAngleBins>0) then
                      if (viewPointPtheta(idirT) == viewPointPphi(idirP).or. &
                           & (viewPointTheta(viewPointPphi(idirP))==viewPointTheta(viewPointPtheta(idirT))) .or. & 
                           & (viewPointPhi(viewPointPtheta(idirT))==viewPointPhi(viewPointPphi(idirP))) ) then
                         grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), enPacket%nuP,viewPointPtheta(idirT)) = &
                              &grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                              & enPacket%nuP,viewPointPtheta(idirT)) +  deltaE(iStar)
                         if (viewPointPtheta(idirT)/=0) grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), & 
                              & enPacket%nuP,0) = &
                              & grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                              & enPacket%nuP,0) +  deltaE(iStar)
                      else
                         grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), & 
                          & enPacket%nuP,0) = &
                          & grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                          & enPacket%nuP,0) +  deltaE(iStar)
                      end if
                   else
                  
                      grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), & 
                           & enPacket%nuP,0) = &
                           & grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                           & enPacket%nuP,0) +  deltaE(iStar)
                      
                   end if
                   
                   return
                end if
                
 
                ! check if the packet is absorbed or scattered 
                if (lgDust) then

                   probSca = grid(gP)%scaOpac(grid(gP)%active(xP,yP,zP),enPacket%nuP)/&
                        & (grid(gP)%opacity(grid(gP)%active(xP,yP,zP),enPacket%nuP))
                   
                   call random_number(random)
                   
                   random = 1.-random

                   if (random > probSca) then
                      lgScattered = .false.         
                   else if (random <= probSca) then
                      lgScattered = .true.         
                   else
                      print*, '! pathSegment: insanity occured and scattering/absorption &
                           & decision stage.'
                      stop
                   end if

                   if (.not. lgScattered) then

                      absInt = absInt + 1.
                            
                      if (.not.lgGas) then

                         ! packet is absobed by the dust
                         packetType = "dustEmi"
                         exit                         

                      else

                         ! packet is absobed by the dust+gas
                         packetType = "diffuse"
                         exit    

                      end if

                   else

                      scaInt = scaInt + 1.                           
                      
                      do nS = 1, nSpecies
                         if (grainabun(nS)>0. .and. grid(gP)%Tdust(nS, 0, & 
                              & grid(gP)%active(xP,yP,zP))<TdustSublime(nS)) exit
                      end do
                      if (nS>7) then
                         print*, "! pathSegment: packet scatters with dust at position where all &
                              &grains have sublimed."
                         print*, xP,yP,zP, grid(gP)%active(xP,yP,zP), tauCell, absTau, passProb
                         stop
                      end if                      

                      ! packet is scattered by the grain
                         
                      ! calculate new direction
                      ! for now assume scattering is isotropic, when phase
                      ! function is introduced the following must be changed                         
                         
                      enPacket%xP(igpp) = xP
                      enPacket%yP(igpp) = yP
                      enPacket%zP(igpp) = zP            
                      
                      if (grid(gP)%active(enPacket%xp(igpp), enPacket%yp(igpp), enPacket%zp(igpp)) < 0.) then
                         print*, "! pathSegment: new packet cannot be emitted from re-mapped cell -1-"
                         print*, "nuP, starPosition(iStar), .false., .true., xp,yp,zp, gp"
                         print*, nuP, starPosition(iStar), .false., .true.,  xp,yp,zp, gp
                         stop
                      end if

                      enPacket = initPhotonPacket(enPacket%nuP, rVec, .false., .false., enPacket%xP(1:2), &
                           & enPacket%yP(1:2), enPacket%zP(1:2), gP)
                      
                      
                      vHat%x = enPacket%direction%x
                      vHat%y = enPacket%direction%y
                      vHat%z = enPacket%direction%z
                      
                      ! initialize optical depth
                      absTau = 0.
                      
                      ! get a random number
                      call random_number(random)
                      
                      ! calculate the probability 
                      passProb = -log(1.-random)
                      
                   end if

                else

                   absInt = absInt + 1.
                   
                   if (.not.lgGas) then
                      print*, "! pathSegment: Insanity occured - no gas present when no dust interaction"
                      stop
                   end if
                   
                   ! packet interacts with gas
                   packetType = "diffuse"
                   exit
                   
                end if
                   
                
             else
          
                ! the packet is not absorbed within this cell
                ! add contribution of the packet to the radiation field
                
                if (enPacket%lgStellar) then
                   grid(gP)%Jste(grid(gP)%active(xP,yP,zP),enPacket%nuP) = &
                        grid(gP)%Jste(grid(gP)%active(xP,yP,zP),enPacket%nuP) + dS*deltaE(iStar) / dV
                else ! if the energy packet is diffuse
                   if (lgDebug) then
                      grid(gP)%Jdif(grid(gP)%active(xP,yP,zP),enPacket%nuP) = &
                           & grid(gP)%Jdif(grid(gP)%active(xP,yP,zP),enPacket%nuP) + dS*deltaE(iStar) / dV
                   else
                      grid(gP)%Jste(grid(gP)%active(xP,yP,zP),enPacket%nuP) = &
                           & grid(gP)%Jste(grid(gP)%active(xP,yP,zP),enPacket%nuP) + dS*deltaE(iStar) / dV
                   end if
                end if
                
                ! update absTau
                absTau = absTau+tauCell

                ! update packet's position
                rVec = rVec+dS*vHat

                ! keep track of where you are on mother grid
                if (gP>1) then

                   if (enPacket%xP(1) <= 0 .or. & 
                        & enPacket%yP(1) <= 0 .or. & 
                        & enPacket%zP(1) <= 0 ) then

                      ! locate where we are at on the mother grid
                      call locate(grid(grid(gP)%motherP)%xAxis, rvec%x, enPacket%xP(1))
                      if ( enPacket%xP(1)< grid(grid(gP)%motherP)%nx) then
                         if ( rvec%x > ( grid(grid(gP)%motherP)%xAxis(enPacket%xP(1)) + &
                              & grid(grid(gP)%motherP)%xAxis(enPacket%xP(1)+1)/2.) ) & 
                              & enPacket%xP(1) = enPacket%xP(1)+1
                      end if                      

                      call locate( grid(grid(gP)%motherP)%yAxis, rvec%y, enPacket%yP(1))
                      if ( enPacket%yP(1)< grid(grid(gP)%motherP)%ny) then
                         if ( rvec%y > ( grid(grid(gP)%motherP)%yAxis(enPacket%yP(1)) + &
                              & grid(grid(gP)%motherP)%yAxis(enPacket%yP(1)+1)/2.) ) & 
                              & enPacket%yP(1) = enPacket%yP(1)+1
                      end if                      

                      call locate(grid(grid(gP)%motherP)%zAxis, rvec%z, enPacket%zP(1))
                      if ( enPacket%zP(1)< grid(grid(gP)%motherP)%nz) then
                         if ( rvec%z > ( grid(grid(gP)%motherP)%zAxis(enPacket%zP(1)) + &
                              & grid(grid(gP)%motherP)%zAxis(enPacket%zP(1)+1)/2.) ) & 
                              & enPacket%zP(1) = enPacket%zP(1)+1
                      end if                      

                      
                   else
                      
                      if (vHat%x>0.) then
                         if ( enPacket%xP(1) < grid(grid(gP)%motherP)%nx ) then
                            if ( rVec%x > (grid(grid(gP)%motherP)%xAxis(enPacket%xP(1))+& 
                                 & grid(grid(gP)%motherP)%xAxis(enPacket%xP(1)+1))/2. ) then
                               enPacket%xP(1) = enPacket%xP(1)+1
                            end if
                         else
                            if ( rVec%x > grid(grid(gP)%motherP)%xAxis(enPacket%xP(1))) then
!                            print*, '! pathSegment: insanity occured at mother grid transfer (x axis +)', & 
!                                 & rVec%x, gP, grid(gP)%motherP
!                            stop
                            end if
                         end if
                      else
                         if ( enPacket%xP(1) > 1 ) then
                            if ( rVec%x <= (grid(grid(gP)%motherP)%xAxis(enPacket%xP(1)-1)+& 
                                 & grid(grid(gP)%motherP)%xAxis(enPacket%xP(1)))/2. ) then
                               enPacket%xP(1) = enPacket%xP(1)-1
                            end if
                         else
                            if (rVec%x < grid(grid(gP)%motherP)%xAxis(1)) then
!                            print*, '! pathSegment: insanity occured at mother grid transfer (x axis-)',&  
!                                 & rVec%x, gP, grid(gP)%motherP
!                            stop
                            end if
                         end if
                      end if
                      if (vHat%y>0.) then
                         if (  enPacket%yP(1) < grid(grid(gP)%motherP)%ny ) then
                            if ( rVec%y > (grid(grid(gP)%motherP)%yAxis( enPacket%yP(1))+& 
                                 & grid(grid(gP)%motherP)%yAxis(enPacket%yP(1)+1))/2. ) then
                               enPacket%yP(1) =  enPacket%yP(1)+1
                            end if
                         else
                            if ( rVec%y > grid(grid(gP)%motherP)%yAxis( enPacket%yP(1))) then
!                            print*, '! pathSegment: insanity occured at mother grid transfer (y axis +)',&
!                                 & rVec%y, gP, grid(gP)%motherP
!                            stop
                            end if
                         end if
                      else
                         if (  enPacket%yP(1) > 1 ) then
                            if ( rVec%y <= (grid(grid(gP)%motherP)%yAxis( enPacket%yP(1)-1)+& 
                                 & grid(grid(gP)%motherP)%yAxis(enPacket%yP(1)))/2. ) then
                               enPacket%yP(1) =  enPacket%yP(1)-1
                            end if
                         else
                            if (rVec%y < grid(grid(gP)%motherP)%yAxis(1)) then
!                            print*, '! pathSegment: insanity occured at mother grid transfer (y axis -)', & 
!                                 & rVec%y, gP, grid(gP)%motherP
!                            stop
                            end if
                         end if
                      end if
                      if (vHat%z>0.) then
                         if (  enPacket%zP(1) < grid(grid(gP)%motherP)%nz ) then
                            if ( rVec%z > (grid(grid(gP)%motherP)%zAxis( enPacket%zP(1))+&
                                 & grid(grid(gP)%motherP)%zAxis(enPacket%zP(1)+1))/2. ) then
                               enPacket%zP(1) =  enPacket%zP(1)+1
                            end if
                         else
                            if ( rVec%z > grid(grid(gP)%motherP)%zAxis( enPacket%zP(1))) then
!                            print*, '! pathSegment: insanity occured at mother grid transfer (z axis +)', &
!                                 & rVec%z, gP, grid(gP)%motherP
!                            stop
                            end if
                         end if
                      else
                         if (  enPacket%zP(1) > 1 ) then
                            if ( rVec%z <= (grid(grid(gP)%motherP)%zAxis( enPacket%zP(1)-1)+&
                                 & grid(grid(gP)%motherP)%zAxis(enPacket%zP(1)))/2. ) then
                               enPacket%zP(1) =  enPacket%zP(1)-1
                            end if
                         else
                            if (rVec%z < grid(grid(gP)%motherP)%zAxis(1)) then
!                        print*, '! pathSegment: insanity occured at mother grid transfer (z axis -)', &
!                             & rVec%z, gP, grid(gP)%motherP
!                        stop
                            end if
                         end if
                      end if
                      
                   end if
                end if

                if (.not.lg1D) then
                   if ( (dS == dSx) .and. (vHat%x > 0.)  ) then
                      xP = xP+1
                   else if ( (dS == dSx) .and. (vHat%x < 0.) ) then
                      xP = xP-1
                   else if ( (dS == dSy) .and. (vHat%y > 0.) ) then
                      yP = yP+1
                   else if ( (dS == dSy) .and. (vHat%y < 0.) ) then 
                      yP = yP-1
                   else if ( (dS == dSz) .and. (vHat%z > 0.) ) then
                      zP = zP+1
                   else if ( (dS == dSz) .and. (vHat%z < 0.) ) then
                      zP = zP-1
                   else
                      print*, '! pathSegment: insanity occured in dS assignement &
                           & [dS,dSx,dSy,dSz,vHat]', dS,dSx,dSy,dSz,vHat
                   end if
                else
                   radius = 1.e10*sqrt((rVec%x/1.e10)*(rVec%x/1.e10) + &
                        & (rVec%y/1.e10)*(rVec%y/1.e10) + &
                        & (rVec%z/1.e10)*(rVec%z/1.e10))
                   call locate(grid(gP)%xAxis, radius , xP)
                   
                end if
                
                ! be 6/6/06
                if(.not.lgPlaneIonization.and..not.lgSymmetricXYZ) then
                   lgReturn=.false.

                   if ( rVec%y <= grid(gP)%yAxis(1)-grid(gP)%geoCorrY .or. yP<1) then

                      ! the energy packet escapes this grid
                      if (gP==1) then
                         yP=1
                         lgReturn=.true.
                      else if (gP>1) then
                         xP = enPacket%xP(grid(gP)%motherP)
                         yP = enPacket%yP(grid(gP)%motherP)
                         zP = enPacket%zP(grid(gP)%motherP)
                         gP = grid(gP)%motherP
                      else
                         print*, '! pathSegment: insanity occured - invalid gP', gP
                         stop
                      end if
                      
                   end if
                   
                   if (rVec%y > grid(gP)%yAxis(grid(gP)%ny)+grid(gP)%geoCorrY .or. yP>grid(gP)%ny) then
                      
                      if (gP==1) then
                         ! the energy packet escapes
                         yP = grid(gP)%ny
                         lgReturn=.true.
                      else if (gP>1) then
                         xP = enPacket%xP(grid(gP)%motherP)
                         yP =  enPacket%yP(grid(gP)%motherP)
                         zP =  enPacket%zP(grid(gP)%motherP)
                         gP = grid(gP)%motherP
                      else
                         print*, '! pathSegment: insanity occured - invalid gP', gP
                         stop
                      end if
                      
                   end if

                   if ( (rVec%x <= grid(gP)%xAxis(1)-grid(gP)%geoCorrX .or. xP<1) .and. gP==1) then
                      xP=1
                      lgReturn=.true.
                      
                   end if
                   
                   
                   if ( (rVec%x <= grid(gP)%xAxis(1)-grid(gP)%geoCorrX .or. xP<1) &
                    & .and. gP>1) then
                      
                      xP = enPacket%xP(grid(gP)%motherP)
                      yP =  enPacket%yP(grid(gP)%motherP)
                      zP =  enPacket%zP(grid(gP)%motherP)
                      gP = grid(gP)%motherP
                      
                   end if
                   
                   
                   if ( (rVec%x >=  grid(gP)%xAxis(grid(gP)%nx)+grid(gP)%geoCorrX &
                        & .or. xP>grid(gP)%nx) .and. gP==1 )then
                      xP = grid(gP)%nx
                      lgReturn=.true.
                      
                   end if
                   
                   if ( (rVec%x >=  grid(gP)%xAxis(grid(gP)%nx)+grid(gP)%geoCorrX&
                        & .or. xP>grid(gP)%nx) .and.  gP>1) then

                      xP = enPacket%xP(grid(gP)%motherP)
                      yP =  enPacket%yP(grid(gP)%motherP)
                      zP =  enPacket%zP(grid(gP)%motherP)
                      gP = grid(gP)%motherP
                      
                   end if
                   
                   if ( (rVec%z <= grid(gP)%zAxis(1)-grid(gP)%geoCorrZ .or.zP<1) &
                        & .and. gP==1) then
                      zP=1
                      lgReturn=.true.
                      
                   end if

                   if ( (rVec%z <= grid(gP)%zAxis(1)-grid(gP)%geoCorrZ &
                        & .or.zP<1) .and. gP>1) then
                      
                      xP = enPacket%xP(grid(gP)%motherP)
                      yP =  enPacket%yP(grid(gP)%motherP)
                      zP =  enPacket%zP(grid(gP)%motherP)
                      gP = grid(gP)%motherP
                      
                   end if
                   
                   if ( (rVec%z >=  grid(gP)%zAxis(grid(gP)%nz)+grid(gP)%geoCorrZ &
                        & .or. zP>grid(gP)%nz) &
                        & .and. gP==1) then
                      
                      zP = grid(gP)%nz
                      lgReturn=.true.
                      
                   end if
                   
                   if ((rVec%z >=  grid(gP)%zAxis(grid(gP)%nz)+grid(gP)%geoCorrZ &
                        & .or. zP>grid(gP)%nz) .and. gP>1) then
                      
                      xP = enPacket%xP(grid(gP)%motherP)
                      yP =  enPacket%yP(grid(gP)%motherP)
                      zP =  enPacket%zP(grid(gP)%motherP)
                      gP = grid(gP)%motherP
                      
                   end if
                   
                   if (lgReturn) then
                      
                      ! the packet escapes without further interaction
                      
                      idirT = int(acos(enPacket%direction%z)/dTheta)+1
                      if (idirT>totangleBinsTheta) then
                         idirT=totangleBinsTheta
                      end if
                      if (idirT<1 .or. idirT>totAngleBinsTheta) then
                         print*, '! energyPacketRun: error in theta direction cosine assignment',&
                              &  idirT, enPacket, dTheta, totAngleBinsTheta
                         stop
                      end if
                      
                      
                      if (enPacket%direction%x<1.e-35) then
                         idirP = 0
                      else
                         idirP = int(atan(enPacket%direction%y/enPacket%direction%x)/dPhi)
                      end if
                      if (idirP<0) idirP=totAngleBinsPhi+idirP
                      idirP=idirP+1
                      
                      if (idirP>totangleBinsPhi) then
                         idirP=totangleBinsPhi
                      end if
                      if (idirP<1 .or. idirP>totAngleBinsPhi) then
                         print*, '! energyPacketRun: error in phi direction cosine assignment',&
                              &  idirP, enPacket, dPhi, totAngleBinsPhi
                         stop
                      end if
                      
                      
                      if (nAngleBins>0) then
                         if (viewPointPtheta(idirT) == viewPointPphi(idirP).or. &
                              & (viewPointTheta(viewPointPphi(idirP))==viewPointTheta(viewPointPtheta(idirT))) .or. &
                              & (viewPointPhi(viewPointPtheta(idirT))==viewPointPhi(viewPointPphi(idirP))) ) then
                            grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), enPacket%nuP,& 
                                 & viewPointPtheta(idirT)) =grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2),& 
                                 & enPacket%nuP,viewPointPtheta(idirT)) +  deltaE(iStar)

                            if (viewPointPtheta(idirT)/=0) grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                                 &enPacket%nuP,0) = &
                                 & grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                                 & enPacket%nuP,0) +  deltaE(iStar)
                            
                         else
                            grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                                 & enPacket%nuP,0) = &
                                 & grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                                 & enPacket%nuP,0) +  deltaE(iStar)
                            
                         end if

                      else
                         
                         grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                              enPacket%nuP,0) = &
                              & grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                              & enPacket%nuP,0) +  deltaE(iStar)
                      end if

                      return
                   end if

                end if

                ! end be 6/6/06


                if(lgPlaneIonization) then
                   lgReturn=.false.
                   
                   if ( rVec%y <= grid(gP)%yAxis(1)-grid(gP)%geoCorrY .or. yP<1) then
                  
                      ! the energy packet escapes this grid
                      if (gP==1) then	
                         yP=1
                         lgReturn=.true.
                      else if (gP>1) then
                         xP = enPacket%xP(1)
                         yP = enPacket%yP(1)
                         zP = enPacket%zP(1)
                         gP = 1
                         igpp = 1
                      else
                         print*, '! pathSegment: insanity occured - invalid gP', gP
                         stop
                      end if
                  
                   end if
               
                   if (rVec%y > grid(gP)%yAxis(grid(gP)%ny)+grid(gP)%geoCorrY .or. yP>grid(gP)%ny) then

                      if (gP==1) then	
                         ! the energy packet escapes
                         yP = grid(gP)%ny
                         lgReturn=.true.
                      else if (gP>1) then
                         xP = enPacket%xP(1)
                         yP = enPacket%yP(1)
                         zP = enPacket%zP(1)
                         gP = 1
                         igpp = 1
                      else
                         print*, '! pathSegment: insanity occured - invalid gP', gP
                         stop
                      end if
                      
                   end if
               
                   if ( (rVec%x <= grid(1)%xAxis(1) .or. xP<1) ) then
                      xP=1
                      rVec%x = grid(gP)%xAxis(1)
                      vHat%x = -vHat%x
                      
                   end if
                   
                   if ( (rVec%x <= grid(gP)%xAxis(1)-grid(gP)%geoCorrX .or. xP<1) &
                        & .and. gP>1) then
                      
                      xP = enPacket%xP(1)
                      yP = enPacket%yP(1)
                      zP = enPacket%zP(1)
                      gP = 1
                      igpp = 1

                   end if
               
                   if ( (rVec%x >=  grid(1)%xAxis(grid(gP)%nx) &
                        & .or. xP>grid(gP)%nx)  )then
                      xP = grid(gP)%nx
                      rVec%x = grid(gP)%xAxis(grid(gP)%nx)
                      vHat%x = -vHat%x
                      
                   end if
               
                   if ( (rVec%x >=  grid(gP)%xAxis(grid(gP)%nx)+grid(gP)%geoCorrX&
                        & .or. xP>grid(gP)%nx) .and.  gP>1) then
                      
                      xP = enPacket%xP(1)
                      yP = enPacket%yP(1)
                      zP = enPacket%zP(1)
                      gP = 1
                      igpp = 1
                   end if
               
                   if ( (rVec%z <= grid(1)%zAxis(1) .or.zP<1) ) then
                      zP=1
                      rVec%z = grid(gP)%yAxis(1)
                      vHat%z = -vHat%z
                      
                   end if
               
                   if ( (rVec%z <= grid(gP)%zAxis(1)-grid(gP)%geoCorrZ &
                        & .or.zP<1) .and. gP>1) then
                      
                      xP = enPacket%xP(1)
                      yP = enPacket%yP(1)
                      zP = enPacket%zP(1)
                      gP = 1
                      igpp = 1
                      
                   end if

                   if ( (rVec%z >=  grid(1)%zAxis(grid(gP)%nz) .or. zP>grid(gP)%nz) &
                        & ) then
                      
                      zP = grid(gP)%nz
                      rVec%z = grid(gP)%zAxis(grid(gP)%nz)
                      vHat%z = -vHat%z
                      
                   end if
               
                   if ((rVec%z >=  grid(gP)%zAxis(grid(gP)%nz)+grid(gP)%geoCorrZ &
                        & .or. zP>grid(gP)%nz) .and. gP>1) then
                      
                      xP = enPacket%xP(1)
                      yP = enPacket%yP(1)
                      zP = enPacket%zP(1)
                      gP = 1
                      igpp = 1
                      
                   end if

                   
                   if (lgReturn) then            

                      ! the packet escapes without further interaction
                      
                      idirT = int(acos(enPacket%direction%z)/dTheta)+1
                      if (idirT>totangleBinsTheta) then
                         idirT=totangleBinsTheta
                      end if
                      if (idirT<1 .or. idirT>totAngleBinsTheta) then
                         print*, '! energyPacketRun: error in theta direction cosine assignment',&
                              &  idirT, enPacket, dTheta, totAngleBinsTheta
                         stop
                      end if
                      
                      
                      if (enPacket%direction%x<1.e-35) then
                         idirP = 0
                      else
                         idirP = int(atan(enPacket%direction%y/enPacket%direction%x)/dPhi)             
                      end if
                      if (idirP<0) idirP=totAngleBinsPhi+idirP
                      idirP=idirP+1
                  
                      if (idirP>totangleBinsPhi) then
                         idirP=totangleBinsPhi
                      end if
                      if (idirP<1 .or. idirP>totAngleBinsPhi) then
                         print*, '! energyPacketRun: error in phi direction cosine assignment',&
                              &  idirP, enPacket, dPhi, totAngleBinsPhi
                         stop
                      end if


                      if (nAngleBins>0) then
                         if (viewPointPtheta(idirT) == viewPointPphi(idirP).or. &
                              & (viewPointTheta(viewPointPphi(idirP))==viewPointTheta(viewPointPtheta(idirT))) .or. & 
                              & (viewPointPhi(viewPointPtheta(idirT))==viewPointPhi(viewPointPphi(idirP))) ) then
                            grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), enPacket%nuP,viewPointPtheta(idirT)) = &
                                 &grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                                 & enPacket%nuP,viewPointPtheta(idirT)) +  deltaE(iStar)
                            if (viewPointPtheta(idirT)/=0) grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), & 
                                 enPacket%nuP,0) = &
                                 & grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                                 & enPacket%nuP,0) +  deltaE(iStar)
                            
                         else
                            grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), & 
                                 enPacket%nuP,0) = &
                             & grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                             & enPacket%nuP,0) +  deltaE(iStar)
                        
                         end if

                      else

                         grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), & 
                              enPacket%nuP,0) = &
                              & grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                              & enPacket%nuP,0) +  deltaE(iStar)   

                      end if
                      
                      return
                   end if
               
                end if

                ! check if the path is still within the simulation region 
                radius = 1.e10*sqrt((rVec%x/1.e10)*(rVec%x/1.e10) + &
                     &                     (rVec%y/1.e10)*(rVec%y/1.e10) + &
                     &                     (rVec%z/1.e10)*(rVec%z/1.e10))

                if (.not.lgPlaneIonization) then

                   if ( (.not.lgSymmetricXYZ .and. (rVec%x<=grid(1)%xAxis(1)-grid(1)%geoCorrX .or.& 
                        & rVec%y<=grid(1)%yAxis(1)-grid(1)%geoCorrY .or. rVec%z<=grid(1)%zAxis(1)-& 
                        & grid(1)%geoCorrZ)) .or.&
                        & (rVec%x >= grid(gP)%xAxis(grid(gP)%nx)+grid(gP)%geoCorrX) .or.&
                        &(rVec%y >= grid(gP)%yAxis(grid(gP)%ny)+grid(gP)%geoCorrY) .or.&
                        &(rVec%z >= grid(gP)%zAxis(grid(gP)%nz)+grid(gP)%geoCorrZ) .or. &
                        & xP>grid(gP)%nx .or. yP>grid(gP)%ny .or. zP>grid(gP)%nz ) then
                  
                  if (gP==1) then

                     if (enPacket%xP(1) > grid(1)%nx) xP = grid(1)%nx
                     if (enPacket%yP(1) > grid(1)%ny) yP = grid(1)%ny
                     if (enPacket%zP(1) > grid(1)%nz) zP = grid(1)%nz
                     if (enPacket%xP(1) < 1) xP = 1
                     if (enPacket%yP(1) < 1) yP = 1
                     if (enPacket%zP(1) < 1) zP = 1
                        

                     ! the energy packet escapes
                        
                     ! the packet escapes without further interaction
                     
                     idirT = int(acos(enPacket%direction%z)/dTheta)+1
                     if (idirT>totangleBinsTheta) then
                        idirT=totangleBinsTheta
                     end if
                     if (idirT<1 .or. idirT>totAngleBinsTheta) then
                        print*, '! energyPacketRun: error in theta direction cosine assignment',&
                             &  idirT, enPacket, dTheta, totAngleBinsTheta
                        stop
                     end if
                         
                     if (enPacket%direction%x<1.e-35) then
                        idirP = 0
                     else
                        idirP = int(atan(enPacket%direction%y/enPacket%direction%x)/dPhi)             
                     end if
                     if (idirP<0) idirP=totAngleBinsPhi+idirP
                     idirP=idirP+1
                     
                     if (idirP>totangleBinsPhi) then
                        idirP=totangleBinsPhi
                     end if
                     
                     if (idirP<1 .or. idirP>totAngleBinsPhi) then
                        print*, '! energyPacketRun: error in phi direction cosine assignment',&
                             &  idirP, enPacket, dPhi, totAngleBinsPhi
                        stop
                     end if
                     
                     if (nAngleBins>0) then
                        if (viewPointPtheta(idirT) == viewPointPphi(idirP).or. &
                             & (viewPointTheta(viewPointPphi(idirP))==viewPointTheta(viewPointPtheta(idirT))) .or. & 
                             & (viewPointPhi(viewPointPtheta(idirT))==viewPointPhi(viewPointPphi(idirP))) ) then
                           grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), enPacket%nuP,& 
                                & viewPointPtheta(idirT)) = &
                                &grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                                & enPacket%nuP,viewPointPtheta(idirT)) +  deltaE(iStar)
                           if (viewPointPtheta(idirT)/=0) grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), & 
                                enPacket%nuP,0) = &
                                & grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                                & enPacket%nuP,0) +  deltaE(iStar)
                        else
                           grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), & 
                                enPacket%nuP,0) = &
                                & grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                                & enPacket%nuP,0) +  deltaE(iStar)
                        end if
                     else
                        
                        grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), & 
                             enPacket%nuP,0) = &
                             & grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                             & enPacket%nuP,0) +  deltaE(iStar)
                        
                     end if
                     
                     !b2.005
                     return

                  else if (gP>1) then

                     xP = enPacket%xP(1)
                     yP = enPacket%yP(1)
                     zP = enPacket%zP(1)
                     gP = 1
                     igpp = 1


                     if (gP/=1) then
                        print*, '! pathSegment: nested multigrids still not implemented'
                        stop
                     end if

                     if ( (radius >= R_out .and. R_out >= 0.) .or.&                   
                          & (rVec%x >= grid(1)%xAxis(grid(1)%nx)+grid(1)%geoCorrX) .or.&      
                          &(rVec%y >= grid(1)%yAxis(grid(1)%ny)+grid(1)%geoCorrY) .or.&       
                          &(rVec%z >= grid(1)%zAxis(grid(1)%nz)+grid(1)%geoCorrZ) .or. &
                          & (.not.lgSymmetricXYZ .and.  (rVec%x<=grid(1)%xAxis(1)-grid(1)%geoCorrX .or.& 
                          & rVec%y<=grid(1)%yAxis(1)-grid(1)%geoCorrY .or. rVec%z<=grid(1)%zAxis(1)-& 
                          & grid(1)%geoCorrZ))) then        


                        if (xP > grid(gP)%nx) xP = grid(gP)%nx
                        if (yP > grid(gP)%ny) yP = grid(gP)%ny
                        if (zP > grid(gP)%nz) zP = grid(gP)%nz
                        
                        if (xP < 1) xP = 1
                        if (yP < 1) yP = 1
                        if (zP < 1) zP = 1
                        
                        ! the energy packet escapes
                        
                        ! the packet escapes without further interaction
                        
                        idirT = int(acos(enPacket%direction%z)/dTheta)+1
                        if (idirT>totangleBinsTheta) then
                           idirT=totangleBinsTheta
                        end if
                        if (idirT<1 .or. idirT>totAngleBinsTheta) then
                           print*, '! energyPacketRun: error in theta direction cosine assignment',&
                                &  idirT, enPacket, dTheta, totAngleBinsTheta
                           stop
                        end if
                        
                        if (enPacket%direction%x<1.e-35) then
                           idirP = 0
                        else
                           idirP = int(atan(enPacket%direction%y/enPacket%direction%x)/dPhi)             
                        end if
                        if (idirP<0) idirP=totAngleBinsPhi+idirP
                        idirP=idirP+1
      
                        if (idirP>totangleBinsPhi) then
                           idirP=totangleBinsPhi
                        end if
                     
                        if (idirP<1 .or. idirP>totAngleBinsPhi) then
                           print*, '! energyPacketRun: error in phi direction cosine assignment',&
                                &  idirP, enPacket, dPhi, totAngleBinsPhi
                           stop
                        end if
                     
                        if (nAngleBins>0) then
                           if (viewPointPtheta(idirT) == viewPointPphi(idirP).or. &
                                &(viewPointTheta(viewPointPphi(idirP))==viewPointTheta(viewPointPtheta(idirT))).or. & 
                                & (viewPointPhi(viewPointPtheta(idirT))==viewPointPhi(viewPointPphi(idirP))) ) then
                              grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), enPacket%nuP,& 
                                   & viewPointPtheta(idirT)) = &
                                   &grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                                   & enPacket%nuP,viewPointPtheta(idirT)) +  deltaE(iStar)
                              if (viewPointPtheta(idirT)/=0) grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), & 
                                   enPacket%nuP,0) = &
                                   & grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                                   & enPacket%nuP,0) +  deltaE(iStar)
                           else
                              grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), & 
                                   enPacket%nuP,0) = &
                                   & grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                                   & enPacket%nuP,0) +  deltaE(iStar)
                           end if
                        else
                           
                           grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), & 
                                enPacket%nuP,0) = &
                                & grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                                & enPacket%nuP,0) +  deltaE(iStar)
                           
                        end if
                        
                        !b2.005
                        return

                     end if
                  else
                     print*, '! pathSegment: insanity occured - invalid gP - ', gP
                     stop
                  end if

               end if

!            if (lgSymmetricXYZ .and. gP == 1) then
               if (lgSymmetricXYZ ) then
                  if (lgPlaneIonization) then
                     print*, '! pathSegment: lgSymmetric and lgPlaneionization flags both raised'
                     stop
                  end if

                  if ( rVec%x <= grid(1)%xAxis(1) .or. (gP==1 .and. xP<1)) then
                     if (vHat%x<0.) vHat%x = -vHat%x 
                     enPacket%xP(1) = 1
                     xP = 1
                     rVec%x = grid(gP)%xAxis(1)
                  end if
                  if ( rVec%y <= grid(1)%yAxis(1) .or. (gP==1 .and. yP<1)) then
                     if (vHat%y<0.) vHat%y = -vHat%y 
                     enPacket%yP(1)=1
                     yP = 1
                     rVec%y = grid(gP)%yAxis(1)
                  end if
                  if ( rVec%z <= grid(1)%zAxis(1) .or. (gP==1 .and. zP<1)) then
                     if (vHat%z<0.) vHat%z = -vHat%z 
                     enPacket%zP(1) = 1
                     zP=1
                     rVec%z = grid(1)%zAxis(1)
                  end if

               end if
            
            end if

            if (gP>1) then
               if ( ( (rVec%x <= grid(gP)%xAxis(1) &
                    &.or. xP<1) .and. vHat%x <=0.) .or. & 
                    & ( (rVec%y <= grid(gP)%yAxis(1) &
                    & .or. yP<1) .and. vHat%y <=0.) .or. & 
                    & ( (rVec%z <= grid(gP)%zAxis(1) &
                    &  .or. zP<1) .and. vHat%z <=0.) .or. & 
                    & ( (rVec%x >= grid(gP)%xAxis(grid(gP)%nx) &
                    &.or. xP>grid(gP)%nx) .and. vHat%x >=0.) .or. & 
                    & ( (rVec%y >= grid(gP)%yAxis(grid(gP)%ny) &
                    & .or. yP>grid(gP)%ny) .and. vHat%y >=0.) .or. & 
                    & ( (rVec%z >= grid(gP)%zAxis(grid(gP)%nz) &
                    &  .or. zP>grid(gP)%nz) .and. vHat%z >=0.) ) then
                      
                  ! go back to mother grid
                  xP = enPacket%xP(1)
                  yP = enPacket%yP(1)
                  zP = enPacket%zP(1)
                  gP = 1
                  igpp = 1

               end if
                      
            end if
            
             


         end if

         if (.not. lgPlaneIonization .and. gP==1 .and. (xP > grid(gP)%nx  &
              & .or. yP > grid(gP)%ny .or. zP > grid(gP)%nz) ) then

            ! the energy packet escapes
         
            ! the packet escapes without further interaction
            
            idirT = int(acos(enPacket%direction%z)/dTheta)+1
            if (idirT>totangleBinsTheta) then
               idirT=totangleBinsTheta
            end if
            if (idirT<1 .or. idirT>totAngleBinsTheta) then
               print*, '! energyPacketRun: error in theta direction cosine assignment',&
                    &  idirT, enPacket, dTheta, totAngleBinsTheta
               stop
            end if
            
            if (enPacket%direction%x<1.e-35) then
               idirP = 0
            else
               idirP = int(atan(enPacket%direction%y/enPacket%direction%x)/dPhi)             
            end if
            if (idirP<0) idirP=totAngleBinsPhi+idirP
            idirP=idirP+1
            
            if (idirP>totangleBinsPhi) then
               idirP=totangleBinsPhi
            end if
            
            if (idirP<1 .or. idirP>totAngleBinsPhi) then
               print*, '! energyPacketRun: error in phi direction cosine assignment',&
                    &  idirP, enPacket, dPhi, totAngleBinsPhi
               stop
            end if
            
            if (nAngleBins>0) then
               if (viewPointPtheta(idirT) == viewPointPphi(idirP).or. &
                    & (viewPointTheta(viewPointPphi(idirP))==viewPointTheta(viewPointPtheta(idirT))) .or. & 
                    & (viewPointPhi(viewPointPtheta(idirT))==viewPointPhi(viewPointPphi(idirP))) ) then
                  grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), enPacket%nuP,& 
                       & viewPointPtheta(idirT)) = &
                       &grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                    & enPacket%nuP,viewPointPtheta(idirT)) +  deltaE(iStar)
                  if (viewPointPtheta(idirT)/=0) grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), & 
                       enPacket%nuP,0) = &
                       & grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                       & enPacket%nuP,0) +  deltaE(iStar)
               else
                  grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), & 
                       enPacket%nuP,0) = &
                       & grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                       & enPacket%nuP,0) +  deltaE(iStar)
               end if
            else
               
               grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), & 
                    enPacket%nuP,0) = &
                    & grid(enPacket%origin(1))%escapedPackets(enPacket%origin(2), &
                    & enPacket%nuP,0) +  deltaE(iStar)
               
            end if
            
            !b2.005
            return
            
            
         end if
         
      end do ! safelimit loop
      
      if (i>= safeLimit) then
         if (.not.lgPlaneIonization) then
            print*, '! pathSegment: [warning] packet trajectory has exceeded&
                 &  maximum number of events', safeLimit, gP, xP,yP,zP, grid(gP)%active(xP,yP,zP), & 
              & rvec, vhat, enPacket, iphot
         end if
         return
         
      end if
      
      if (gP==1) then
         igpp = 1
      else if (gP>1) then
         igpp = 2 
      else
         print*, "! pathSegment: insane grid index "
         stop
      end if

      enPacket%xP(igpp) = xP
      enPacket%yP(igpp) = yP
      enPacket%zP(igpp) = zP   
      
   ! the energy packet has beenid absorbed - reemit a new packet from this position
   call energyPacketRun(packetType, rVec, enPacket%xP(1:2), enPacket%yP(1:2), &
        & enPacket%zP(1:2), gP)
   
   return
   
 end subroutine pathSegment
 

end subroutine energyPacketDriver

         
 end module photon_mod


