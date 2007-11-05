! $Id: lightning_nox_nl_mod.f,v 1.8 2007/11/05 20:23:52 bmy Exp $
      MODULE LIGHTNING_NOX_NL_MOD
!
!******************************************************************************
!  Module LIGHTNING_NOX_MOD contains variables and routines for emitting NOx
!  from lightning into the atmosphere.  Original code comes from the old 
!  GISS-II CTM's of Yuhang Wang, Gerry Gardner, & Larry Horowitz.  Overhauled 
!  for updated parameterization schemes: CTH, MFLUX and PRECON.  Now also
!  uses the near-land formulation (i.e. offshore boxes also get treated as
!  if they were land boxes).  (ltm, rch, bmy, 4/14/04, 3/27/07)  
!
!  NOTE: The OTD/LIS regional redistribution for MFLUX and PRECON lightning
!  parameterizations have not yet been implemented.  These parameterizations
!  do not yield realistic results with the GEOS-4 meteorology.  We will try
!  to implement them for GEOS-5 at a later time. (rch, ltm, bmy, 3/27/07)
!
!  Module Variables:
!  ============================================================================
!  (1 ) NL_NBOR        (INTEGER) : # of neighbor boxes to check for near-land 
!  (2 ) NL_THRESH      (REAL*8 ) : LWI threshold for near-land criterion
!  (3 ) NNLIGHT        (INTEGER) : # of vertical points in lightning CDF's
!  (4 ) NLTYPE         (INTEGER) : Types of lightning to consider
!  (5 ) PROFILE        (REAL*8 ) : Array to hold lightning CDF's read from disk
!  (6 ) SLBASE         (REAL*8 ) : Array to hold NOx lightning emissions
!  (7 ) OTD_LOC_REDIST (REAL*8 ) : Array to hold OTD/LIS local redist values
!  (8 ) OTD_LOC_REDIST (REAL*8 ) : Array to hold OTD/LIS regional redist values
!  (9 ) RFLASH_MIDLAT  (REAL*8 ) : NOx molec/flash/meter (500 mol/flash Tg N/y)
!  (10) RFLASH_TROPIC  (REAL*8 ) : NOx molec/flash/meter (previous definition)
!  (11) EAST_WEST_DIV  (REAL*8 ) : Longitude between "AMERICAS" & "EURASIA"
!  (12) WEST_NS_DIV    (REAL*8 ) : Latitude boundary of AMERICAN TROPICS
!  (13) EAST_NS_DIV    (REAL*8 ) : Latitude boundary of EURASIAN TROPICS
!  (14) T_NEG_BOT      (REAL*8 ) : Temp at bottom of neg. charge layer = 273 K
!  (15) T_NEG_CTR      (REAL*8 ) : Temp at center of neg. charge layer = 258 K
!  (16) T_NEG_TOP      (REAL*8 ) : Temp at top    of neg. charge layer = 233 K
!  (17) AREA_30N       (REAL*8 ) : Grid box surface area at 30 N [m2]
!  (18) FLASH_SCALE    (REAL*8 ) : Global scaling factor for LNOx to 6 Tg N/yr
!
!  Module Routines:
!  ============================================================================
!  (1 ) LIGHTNING_NL             : Driver routine for lightning emissions
!  (2 ) LIGHTDIST                : Partitions NOx vertically w/ Pickering CDF's
!  (3 ) FLASHES_CTH              : Computes flash rate via CTH scheme
!  (4 ) FLASHES_MFLUX            : Computes flash rate via MFLUX scheme
!  (5 ) FLASHES_PRECON           : Computes flash rate via PRECON scheme
!  (6 ) GET_IC_CG_RATIO          : Gets inter-cloud/cloud-ground flash ratio 
!  (7 ) READ_REGIONAL_REDIST     : Reads OTD-LIS regional redistrib. factors
!  (8 ) READ_LOCAL_REDIST        : Reads OTD-LIS local redistrib. factors
!  (9 ) EMLIGHTNING_NL           : Saves lightning NOx into GEMISNOX array
!  (10) GET_FLASH_SCALE_CTH      : Returns CTH scaling factor to 6 Tg N/yr
!  (11) GET_FLASH_SCALE_MFLUX    : Returns MFLUX scaling factor to 6 Tg N/yr
!  (12) GET_FLASH_SCALE_PRECON   : Returns PRECON scaling factor to 6 Tg N/yr
!  (13) INIT_LIGHTNING_NOX_NL    : Zeroes module arrays and reads CDF data
!  (14) CLEANUP_LIGHTNING_NOX_NL : Deallocates all module arrays
!
!  GEOS-CHEM modules referenced by lightning_nox_mod.f
!  ============================================================================
!  (1 ) bpch2_mod.f              : Module w/ routines for binary punch file I/O
!  (2 ) dao_mod.f                : Module w/ arrays for DAO met fields
!  (3 ) diag_mod.f               : Module w/ GEOS-Chem diagnostic arrays
!  (4 ) directory_mod.f          : Module w/ GEOS-Chem data & metfld dirs
!  (5 ) error_mod.f              : Module w/ I/O error and NaN check routines
!  (6 ) file_mod.f               : Module w/ file unit numbers and error checks
!  (7 ) grid_mod.f               : Module w/ horizontal grid information
!  (8 ) logical_mod.f            : Module w/ GEOS-Chem logical switches
!  (9 ) pressure_mod.f           : Module w/ routines to compute P(I,J,L)
!  (10) transfer_mod.f           : Module w/ routines to cast & resize arrays
!
!  References:
!  ============================================================================
!  (1 ) Price & Rind (1992), JGR, vol. 97, 9919-9933.
!  (2 ) Price & Rind (1994), M. Weather Rev, vol. 122, 1930-1939.
!  (3 ) Allen & Pickering (2002), JGR, vol. 107, NO. D23, 4711, 
!        doi:10.1029/2002JD002066
!  (4 ) Hudman et al (2007), JGR, in press (as of 3/27/07)
!
!  NOTES:
!  (1 ) Based on "lightning_nox_mod.f", but updated for near-land formulation
!        and for CTH, MFLUX, PRECON parameterizations (ltm, bmy, 5/10/06)
!  (2 ) Now move computation of IC/CG flash ratio out of routines FLASHES_CTH, 
!        FLASHES_MFLUX, FLASHES_PRECON, and into routine GET_IC_CG_RATIO.
!        Added a fix in LIGHTDIST for pathological grid boxes.  Set E_IC_CG=1 
!        according to Allen & Pickering [2002].  Rename OTDSCALE array to
!        OTD_REG_REDIST, and also add OTD_LOC_REDIST array.  Now scale 
!        lightning to 6 Tg N/yr for both 2x25 and 4x5.  Rename routine
!        GET_OTD_LIS_REDIST to GET_REGIONAL_REDIST.  Add similar routine
!        GET_LOCAL_REDIST.  Removed GET_OTD_LOCp AL_REDIST.  Bug fix: divide 
!        A_M2 by 1d6 to get A_KM2. (rch, ltm, bmy, 2/22/07)
!  (3 ) Rewritten for separate treatment of LNOx emissions at tropics & 
!        midlatitudes, based on Hudman et al 2007.  Removed obsolete
!        variable E_IC_CG. (rch, ltm, bmy, 3/27/07)
!******************************************************************************
!
      IMPLICIT NONE

      !=================================================================
      ! MODULE PRIVATE DECLARATIONS -- keep certain internal variables 
      ! and routines from being seen outside "lightning_nox_f_nl_mod.f"
      !=================================================================

      ! Make everything PRIVATE ...
      PRIVATE

      ! ... except these routines
      PUBLIC :: LIGHTNING_NL
      PUBLIC :: EMLIGHTNING_NL
      PUBLIC :: CLEANUP_LIGHTNING_NOX_NL

      !=================================================================
      ! MODULE VARIABLES
      !=================================================================

      ! Scalars
      INTEGER              :: NNLIGHT
      INTEGER              :: NL_NBOR  
      REAL*8               :: NL_THRESH
      REAL*8               :: AREA_30N
      REAL*8               :: FLASH_SCALE

      ! Parameters
      INTEGER, PARAMETER   :: NLTYPE        = 3
      !--------------------------------------------------------------------
      ! Prior to 3/27/07:
      !REAL*8,  PARAMETER   :: E_IC_CG       = 1d0
      !REAL*8,  PARAMETER   :: RFLASH        = 2.073d22
      !--------------------------------------------------------------------
      REAL*8,  PARAMETER   :: RFLASH_MIDLAT = 3.011d26   ! 500 mol/flash
      REAL*8,  PARAMETER   :: RFLASH_TROPIC = 2.073d22   ! same as old RFLASH
      REAL*8,  PARAMETER   :: EAST_WEST_DIV = -30d0
      REAL*8,  PARAMETER   :: WEST_NS_DIV   =  23d0
      REAL*8,  PARAMETER   :: EAST_NS_DIV   =  35d0
      REAL*8,  PARAMETER   :: T_NEG_BOT     = 273.0d0    !   0 C 
      REAL*8,  PARAMETER   :: T_NEG_CTR     = 258.0d0    ! -15 C
      REAL*8,  PARAMETER   :: T_NEG_TOP     = 233.0d0    ! -40 C

      ! Arrays
      REAL*8,  ALLOCATABLE :: PROFILE(:,:)
      REAL*8,  ALLOCATABLE :: SLBASE(:,:,:)
      REAL*8,  ALLOCATABLE :: OTD_REG_REDIST(:,:)
      REAL*8,  ALLOCATABLE :: OTD_LOC_REDIST(:,:)

      !=================================================================
      ! MODULE ROUTINES -- follow below the "CONTAINS" statement 
      !=================================================================
      CONTAINS

!------------------------------------------------------------------------------

      SUBROUTINE LIGHTNING_NL
!
!******************************************************************************
!  Subroutine LIGHTNING_NL uses Price & Rind's formulation for computing
!  NOx emission from lightning.  This has been modified to use the near-land
!  formulation (i.e. offshore boxes get treated as if they were land boxes).
!  (ltm, bmy, 5/10/06, 1/31/07)
!
!  Output Lightning NOX [molec/cm3/s] is stored in the GEMISNOX array.
!
!  NOTES:
!  (1 ) Now recompute the cold cloud thickness according to updated formula 
!        from Lee Murray.  Rearranged argument lists to routines FLASHES_CTH, 
!        FLASHES_MFLUX, FLASHES_PRECON.  Now call READ_REGIONAL_REDIST and
!        READ_LOCAL_REDIST. Updated comments accordingly.  Now apply 
!        FLASH_SCALE to scale the total lightning NOx to 6 Tg N/yr.  Now apply
!        OTD/LIS regional or local redistribution (cf. B. Sauvage) to the ND56 
!        diagnostic. lightning redistribution to the ND56 diag.  Renamed
!        REGSCALE variable to REDIST.  Bug fix: divide A_M2 by 1d6 to get
!        A_KM2. (rch, ltm, bmy, 2/14/07)
!  (3 ) Rewritten for separate treatment of LNOx emissions at tropics & 
!        midlatitudes (rch, ltm, bmy, 3/27/07)
!******************************************************************************
!      
      ! References to F90 modules
      USE DAO_MOD,      ONLY : BXHEIGHT,  CLDTOPS,    PRECON,   T, ZMMU
      USE DIAG56_MOD,   ONLY : AD56,      ND56
      !---------------------------------------------------------------------
      ! Prior to 3/27/07:
      !USE GRID_MOD,     ONLY : GET_YMID,  GET_AREA_M2
      !---------------------------------------------------------------------
      USE GRID_MOD,     ONLY : GET_YMID,  GET_XMID,   GET_AREA_M2
      USE LOGICAL_MOD,  ONLY : LCTH,      LMFLUX,     LOTDLOC
      USE LOGICAL_MOD,  ONLY : LOTDREG,   LPRECON
      USE PRESSURE_MOD, ONLY : GET_PEDGE, GET_PCENTER
      USE TIME_MOD,     ONLY : GET_MONTH, GET_SEASON

#     include "CMN_SIZE"     ! Size parameters
#     include "CMN_GCTM"     ! Physical constants

      ! Local variables
      LOGICAL, SAVE         :: FIRST      = .TRUE.
      INTEGER, SAVE         :: LASTMONTH  = -1
      INTEGER, SAVE         :: LASTSEASON = -1
      INTEGER               :: I,         J,           L,        LCHARGE
      INTEGER               :: LMAX,      LTOP,        LBOTTOM,  L_MFLUX
      INTEGER               :: MONTH,     SEASON,      YEAR
      REAL*8                :: A_KM2,     A_M2,        CC,       DLNP     
      REAL*8                :: DZ,        FLASHRATE,   H0,       HBOTTOM
      REAL*8                :: HCHARGE,   IC_CG_RATIO, MFLUX,    P1
      REAL*8                :: P2,        P3,          RAIN,     RATE
      REAL*8                :: RATE_SAVE, REDIST,      T1,       T2
      REAL*8                :: TOTAL,     TOTAL_CG,    TOTAL_IC, X       
      REAL*8                :: YMID,      Z_IC,        Z_CG,     ZUP
      REAL*8                :: XMID
      REAL*8                :: VERTPROF(LLPAR)

      ! Mid-latitude top-down scaling factor (see Sec. 6 for documentation)
      ! (ltm, rch, bmy, 3/27/07)
#if   defined( GRID4x5 )
      REAL*8, PARAMETER     :: MID_LAT_SCALE = 0.6731d0 
#elif defined( GRID2x25 )
      REAL*8, PARAMETER     :: MID_LAT_SCALE = 0.2693d0 
#endif

      !=================================================================
      ! LIGHTNING_NL begins here!
      !=================================================================

      ! First-time initialization
      IF ( FIRST ) THEN
         CALL INIT_LIGHTNING_NOX_NL
         FIRST = .FALSE.
      ENDIF

      ! LMAX: the highest L-level to look for lightning (usually LLPAR-1)
      LMAX   = LLPAR - 1

      ! Get current month
      MONTH  = GET_MONTH()

      ! Get current season
      SEASON = GET_SEASON()

      IF ( LOTDREG ) THEN
         
         ! OTD-LIS regional redistribution: read monthly scale factors
         IF ( MONTH /= LASTMONTH ) THEN
            CALL READ_REGIONAL_REDIST( MONTH )
            LASTMONTH = MONTH
         ENDIF

      ELSE IF ( LOTDLOC ) THEN

         ! OTD-LIS local redistribution: read seasonal scale factors
         IF ( SEASON /= LASTSEASON ) THEN
            CALL READ_LOCAL_REDIST( SEASON )
            LASTSEASON = SEASON
         ENDIF

      ENDIF

      ! Array containing molecules NOx / grid box / 6h. 
      SLBASE = 0d0

      !=================================================================
      ! Compute lightning emissions for each (I,J) column
      !=================================================================

!$OMP PARALLEL DO
!$OMP+DEFAULT( SHARED )
!$OMP+PRIVATE( I,           J,        L,        A_M2,   A_KM2     )
!$OMP+PRIVATE( YMID,        XMID,     LCHARGE,  P1,     P2        )
!$OMP+PRIVATE( T1,          T2,       DLNP,     DZ,     P3        )
!$OMP+PRIVATE( ZUP,         HCHARGE,  LTOP,     H0,     Z_CG      )
!$OMP+PRIVATE( Z_IC,        LBOTTOM,  HBOTTOM,  CC,     FLASHRATE )
!$OMP+PRIVATE( IC_CG_RATIO, L_MFLUX,  MFLUX,    RAIN,   RATE      )
!$OMP+PRIVATE( X,           TOTAL_IC, TOTAL_CG, TOTAL,  REDIST    )
!$OMP+PRIVATE( RATE_SAVE,   VERTPROF                              )
!$OMP+SCHEDULE( DYNAMIC )

      ! Loop over latitudes
      DO J = 1, JJPAR

         ! Grid box surface areas in [m2] and [km2]
         A_M2  = GET_AREA_M2( J )
         A_KM2 = A_M2 / 1d6

         ! Grid box latitude [degrees]
         YMID  = GET_YMID( J )

         ! Loop over longitudes
         DO I = 1, IIPAR

            ! Grid box longitude [degrees]
            XMID     = GET_XMID( I )

            ! Initialize
            LBOTTOM  = 0
            LCHARGE  = 0
            CC       = 0d0
            HCHARGE  = 0d0
            HBOTTOM  = 0d0
            REDIST   = 0d0
            TOTAL    = 0d0
            TOTAL_IC = 0d0
            TOTAL_CG = 0d0

            !===========================================================
            ! (1) FIND NEGATIVE CHARGE LAYER
            !
            ! LCHARGE is the L-value where the negative charge layer is
            ! found.  According to Williams (1985), the negative charge
            ! layer occurs where T is between 0 C and -40 C.  The 
            ! original model code set this at -10 C, but according to 
            ! Houze (1993), a good proxy for the negative charge layer
            ! maximum density is at -15 C.
            !
            ! Also of interest for later, will be the bottom of the
            ! negative charge layer (i.e., temp = 0 C) in calculating 
            ! the cold cloud depth.
            !
            ! If LCHARGE=1, then it is too cold to have water droplets
            ! in the column, so there will be no lightning events,
            ! and we go to the next (I,J) box.
            !
            ! (ltm, bmy, 5/10/06, 12/11/06)
            !===========================================================

            ! Find negative charge layer
            DO L = 1, LMAX
               IF ( T(I,J,L) <= T_NEG_CTR ) THEN
                  LCHARGE = L
                  EXIT
               ENDIF
            ENDDO

            ! Error check LCHARGE
            IF ( LCHARGE >= LMAX ) LCHARGE = LMAX
            IF ( LCHARGE <= 1    ) CYCLE

            !-----------------------------------------------------------
            ! (1a) Define more quantities
            !-----------------------------------------------------------
           
            ! Pressure [hPa] at the centers of grid
            ! boxes (I,J,LCHARGE-1) and (I,J,LCHARGE)
            P1   = GET_PCENTER( I, J, LCHARGE-1 )
            P2   = GET_PCENTER( I, J, LCHARGE   )

            ! Temperatures [K] at the centers of grid
            ! boxes (I,J,LCHARGE-1) and (I,J,LCHARGE)
            T1   = T(I,J,LCHARGE-1)
            T2   = T(I,J,LCHARGE  )
 
            ! DZ is the height [m] from the center of box (I,J,LCHARGE-1)
            ! to the negative charge layer.  It may be found in either
            ! the (LCHARGE)th sigma layer or the (LCHARGE-1)th layer.
            ! We use the hypsometric eqn to find the distance between
            ! the center of (LCHARGE)th and (LCHARGE-1)th boxes, then
            ! assume a linear temp distribution to scale between the two.
            DLNP = LOG( P1 / P2 ) / ( T1 - T2 ) * ( T1 - T_NEG_CTR )
            DZ   = Rdg0 * ( ( T1 + T2 ) / 2d0 ) * DLNP

            ! Pressure [hPa] at the bottom edge of box (I,J,LCHARGE),
            ! or, equivalently, the top edge of box (I,J,LCHARGE-1).
            P3   = GET_PEDGE( I, J, LCHARGE )

            ! Height [m] from the center of grid box (I,J,LCHARGE-1) 
            ! to the top edge of grid box (I,J,LCHARGE-1)
            ZUP  = Rdg0 * T1 * LOG( P1 / P3 )

            !-----------------------------------------------------------
            ! (1b) HCHARGE is the height of the negative charge layer 
            ! above the bottom edge of box (I,J,LCHARGE).  
            ! 
            ! If DZ < ZUP, then DZ is in grid box (I,J,LCHARGE-1);
            ! therefore subtract 1 from LCHARGE and compute HCHARGE 
            ! accordingly.  
            !
            ! In this case, please note that BXHEIGHT(I,J,LCHARGE)-ZUP 
            ! is the distance from the bottom edge of the grid box to 
            ! the center of the newly defined (LCHARGE)th layer.
            !-----------------------------------------------------------
            IF ( DZ >= ZUP ) THEN
               HCHARGE = DZ - ZUP
            ELSE
               LCHARGE = LCHARGE - 1
               HCHARGE = ( BXHEIGHT(I,J,LCHARGE) - ZUP ) + DZ
            ENDIF

            !===========================================================
            ! (2) COMPUTE CONVECTIVE CLOUD TOP HEIGHT
            !
            ! LTOP is the L-layer where the convective cloud top is 
            ! found.  The cloud top is located at the highest sigma 
            ! level for which the cloud mass flux is nonzero.  Since 
            ! GMAO cloud mass flux is defined at the top of each sigma 
            ! level, the convective cloud top is located at the top 
            ! edge of layer LTOP.
            !
            ! For lightning to exist, the cloud must straddle the 
            ! negative charge layer (in other words, at the very 
            ! minimum, the cloud bottom must occur in the LCHARGEth 
            ! layer).  If LTOP < LCHARGE go to the next (I,J) location.
            ! 
            ! Additionally, because the negative charge layer extends 
            ! from 0 C to around -40 C (Williams 1985), any cloud type 
            ! heights that are not colder than -40 C will be considered 
            ! unable to create the necessary dipole.  Therefore, if 
            ! T(I,J,LTOP) >= -40 C, go to the next (I,J) location. 
            !
            ! (ltm, bmy, 5/10/06, 12/11/06)
            !===========================================================

            ! Cloud top level
            LTOP = CLDTOPS(I,J)

            ! Error check LTOP as described above
            IF ( LTOP        >  LMAX      ) LTOP = LMAX
            IF ( LTOP        <  LCHARGE   ) CYCLE
            IF ( T(I,J,LTOP) >= T_NEG_TOP ) CYCLE 

            ! H0 is the convective cloud top height [m].  This is the
            ! distance from the surface to the top edge of box (I,J,LTOP).
            H0   = SUM( BXHEIGHT(I,J,1:LTOP) )

            ! Z_CG is the cloud-ground path (ground --> HCHARGE) [m]
            Z_CG = SUM( BXHEIGHT(I,J,1:LCHARGE-1)  ) + HCHARGE

            ! Z_IC is the intra-cloud path (HCHARGE --> cloud top) [m]
            Z_IC = SUM( BXHEIGHT(I,J,LCHARGE:LTOP) ) - HCHARGE

            !===========================================================
            ! (3) COMPUTE COLD CLOUD THICKNESS
            ! 
            ! Find the cold cloud thickness (CC) -- the distance from 
            ! where the temperature is 0 C up to the top of the cloud.  
            ! This is necessary for calculating the f_CG/f_IC ratio as 
            ! per Price and Rind 1993.  
            !
            ! This is a clone of the method above to find height to 
            ! HCHARGE, and we can recycle many of the same variables 
            ! that aren't used again.
            ! 
            ! Grid box (I,J,LBOTTOM) is the model layer where the 
            ! temperature of the cloud is 0C.
            !
            ! NOTE: If no temperature in the column is above 0 C, it 
            ! moves on to the next (I,J) box as before with the -15 C.
            !
            ! (ltm, bmy, 5/10/06, 12/11/06)
            !===========================================================

            ! Find the level where T = 0 C
            DO L = 1, LMAX
               IF ( T(I,J,L) <= T_NEG_BOT ) THEN
                  LBOTTOM = L
                  EXIT
               ENDIF
            ENDDO

            ! Error check LBOTTOM as described above
            IF ( LBOTTOM >= LMAX ) LBOTTOM = LMAX
            IF ( LBOTTOM <= 1    ) CYCLE 

            !-----------------------------------------------------------
            ! (3a) Define more quantities
            !-----------------------------------------------------------

            ! Pressure [hPa] at the centers of grid
            ! boxes (I,J,LBOTTOM-1) and (I,J,LBOTTOM)
            P1   = GET_PCENTER( I, J, LBOTTOM-1 )
            P2   = GET_PCENTER( I, J, LBOTTOM   )

            ! Temperature [K] at the centers of grid
            ! boxes (I,J,LBOTTOM-1) and (I,J,LBOTTOM)
            T1   = T(I,J,LBOTTOM-1)
            T2   = T(I,J,LBOTTOM  )
       
            ! DZ is the height [m] from the center of box (I,J,LCHARGE-1)
            ! to the negative charge layer.  It may be found in either
            ! the (LCHARGE)th sigma layer or the (LCHARGE-1)th layer.
            ! We use the hypsometric eqn to find the distance between
            ! the center of (LCHARGE)th and (LCHARGE-1)th boxes, then
            ! assume a linear temp distribution to scale between the two.
            DLNP = LOG( P1 / P2 ) / ( T1 - T2 ) * ( T1 - T_NEG_BOT )
            DZ   = Rdg0 * ( ( T1 + T2 ) / 2d0 ) * DLNP

            ! Pressure [hPa] at the bottom edge of box (I,J,LBOTTOM),
            ! or, equivalently, the top edge of box (I,J,BOTTOM-1).
            P3   = GET_PEDGE( I, J, LBOTTOM )

            ! Height [m] from the center of grid box (I,J,LBOTTOM-1) 
            ! to the top edge of grid box (I,J,LBOTTOM-1)
            ZUP  = Rdg0 * T1 * LOG( P1 / P3 )

            !-----------------------------------------------------------
            ! (3b) HBOTTOM is the height of the 0 C layer above the 
            ! bottom edge of box (I,J,LBOTTOM).  
            ! 
            ! If DZ < ZUP, then DZ is in grid box (I,J,LBOTTOM-1);
            ! therefore subtract 1 from LBOTTOM and compute HBOTTOM
            ! accordingly.
            !
            ! In this case, please note that BXHEIGHT(I,J,LBOTTOM)-ZUP 
            ! is the distance from the bottom edge of the grid box to 
            ! the center of the newly defined (LBOTTOM)th layer.
            !-----------------------------------------------------------
            IF ( DZ >= ZUP ) THEN
               HBOTTOM = DZ - ZUP
            ELSE
               LBOTTOM = LBOTTOM - 1
               HBOTTOM = ( BXHEIGHT(I,J,LBOTTOM) - ZUP ) + DZ
            ENDIF
  
            ! Cold cloud thickness is difference of cloud top 
            ! height (H0) and the height to the bottom.
            CC = H0 - SUM( BXHEIGHT(I,J,1:LBOTTOM-1) ) - HBOTTOM 

            !===========================================================
            ! (4) COMPUTE IC/CG FLASH_RATIO FROM COLD-CLOUD DEPTH
            !
            ! This is necessary as an input for the MFLUX and PRECON
            ! parameterizations, as well as for determining the fraction 
            ! of LNOX generated by either type of flash, and will
            ! eventually be used for separate vertical distributions
            ! when they become available.  (ltm, bmy, 12/11/06)
            !===========================================================
			
            ! Get Inter-Cloud/Cloud-Ground flash ratio [unitless]
            IC_CG_RATIO = GET_IC_CG_RATIO( CC )

            !===========================================================
            ! (5) COMPUTE LIGHTNING FLASH RATES
            !
            ! Now that we have computed the the ratio of intra-cloud
            ! flashes to cloud-ground flashes, compute the lightning
            ! flash rate via one of these parameterizations:
            !
            ! (a) Cloud top height (CTH)
            ! (b) Mass flux (MFLUX)
            ! (c) Convective Precpitation (PRECON)
            ! 
            ! (ltm, bmy, 5/10/06, 12/11/06)
            !===========================================================

            IF ( LCTH ) THEN

               !--------------------------------------------------------
               ! (5a) CLOUD TOP HEIGHT PARAMETERIZATION (all met fields)
               !
               ! Based on Price & Rind (1992).
               !--------------------------------------------------------

               ! Get lightning flash rate per minute and IC/CG ratio
               CALL FLASHES_CTH( I, J, H0, FLASHRATE )

            ELSE IF ( LMFLUX ) THEN

               !--------------------------------------------------------
               ! (5b) MFLUX PARAMETERIZATION (GEOS-4 only)
               !
               ! Call FLASHES_MFLUX to return the # of lightning 
               ! flashes per minute.  ZMMU has to be converted from 
               ! [Pa/s] to [kg/m2/min] to match the literature.  The 
               ! conversion involves dividing by g and multiplying by 
               ! a time conversion factor of 60 sec/min.
               !
               ! MFLUX is defined as the vertical mass flux at the 
               ! first box with a pressure at the 0.44 sigma level 
               ! (~440 hPa).  Allen et al [2002].  Sigma level 0.44 
               ! (from GEOS-STRAT) was chosen because it limits 
               ! lightning production to deep convective clouds.
               !
               ! For now hardwire the L_MFLUX value, since at L = 9 in
               ! GEOS-4, sig mid = 0.433887, pressure ~ 433.893 hPa,
               ! and altitude ~ 6.591 km.  Later, include a loop to run
               ! through L-values until one is close to sig=0.44 for 
               ! more compatability.
               !--------------------------------------------------------

               ! Layer where MFLUX is taken
               L_MFLUX = 9

               ! Convert from [Pa/s] --> [kg/m2/min]
               MFLUX   = ZMMU( I, J, L_MFLUX ) * 60.0d0 / g0

               ! Get lightning flash rate per minute and IC/CG ratio
               CALL FLASHES_MFLUX( I, J, MFLUX, IC_CG_RATIO, FLASHRATE )

            ELSE IF ( LPRECON ) THEN

               !--------------------------------------------------------
               ! (5c) PRECON PARAMETERIZATION (all met fields)
               !--------------------------------------------------------

               ! Convective precip [mm H2O/day]
               RAIN = PRECON( I, J )

               ! Get lightning flash rate per minute and IC/CG ratio
               CALL FLASHES_PRECON( I, J, RAIN, IC_CG_RATIO, FLASHRATE )
               
            ENDIF

            !===========================================================
            ! (6) COMPUTE TOTAL LNOx AND PARTITION INTO VERTICAL LAYERS
            ! 
            ! (6a) We convert FLASHRATE (computed above) to units of
            ! [flashes/6h] and store in the RATE variable.
            !
            ! We then multiply RATE by a scale factor based on 
            ! OTD/LIS observations.  This is necessary in order to make 
            ! sure that the lightning flashes happen in the correct 
            ! locations as diagnosed by OTD/LIS satellite observations.  
            ! There are two redistribution options:
            !
            !   (1) Apply regional scale factors based on OTD/LIS
            !        observations (method of L. Jourdain et al)
            !
            !   (2) Apply box-by-box scale scale factors based on
            !        OTD/LIS observations (method of B. Sauvage)
            !
            ! NOTE: As of 3/27/07, only method (1) is implemented.
            ! 
            ! (6b) We then compute X, which is the ratio
            !   [cloud-ground flashes / total flashes].
            !
            ! The amount of lightning released will depend whether we
            ! are in the tropics or in mid-latitudes.
            !
            !
            ! (6c) LIGHTNING NOx EMISSIONS IN THE TROPICS:
            ! ----------------------------------------------------------
            ! N. American / S. American     tropics: lat <= 23 N 
            ! African / Oceanian / Eurasian tropics: lat <= 35 N
            !
            ! The lightning NOx released in the inter-cloud (IC) and 
            ! cloud-ground (CG) paths are given by:
            !
            !   TOTAL_IC = RFLASH_TROPIC * RATE * (1-X) * Z_IC
            !   TOTAL_CG = RFLASH_TROPIC * RATE * (  X) * Z_CG
            !
            ! where:
            !   RFLASH_TROPIC = # of NOx molecules released per flash 
            !                    per meter (same as in previous code)
            !   RATE          = lightning flashes / 6h computed above
            !   Z_IC          = IC pathway in meters (from the negative    
            !                    cloud layer to the cloud top)
            !   Z_CG          = CG pathway in meters (from the negative
            !                    cloud layer to the ground surface)
            !   
            ! We also apply a top-down final global scaling factor, 
            ! calculated by previously bringing total global LNOx to 
            ! 6 Tg N/yr  (2x2.5: 0.3683, 4x5: 0.8996).  In 2004, the 
            ! tropics-only contribution to LNOx was 4.5379 Tg N.
            !
            ! 
            ! (6d) LIGHTING NOx EMISSIONS AT MIDLATITUDES:
            ! ----------------------------------------------------------
            ! N. American midlatitudes : lat > 23N
            ! Eurasian    midlatitudes : lat > 35N
            !
            ! The lightning NOx released at midlatitudes is independent
            ! of path length.  Thus:
            !
            !   TOTAL_IC = RFLASH_MIDLAT * RATE * (1-X) * MID_LAT_SCALE
            !   TOTAL_CG = RFLASH_MIDLAT * RATE *    X  * MID_LAT_SCALE
            !
            ! where 
            !   RFLASH_MIDLAT = # of NOx molecules released per flash 
            !                    per meter (based on 500 mol/flash)
            !   RATE          = lightning flashes / 6h computed above
            !   Z_IC          = IC pathway in meters (from the negative    
            !                    cloud layer to the cloud top)
            !   Z_CG          = CG pathway in meters (from the negative
            !                    cloud layer to the ground surface)
            !
            ! We now emit at the Northern Mid-latitudes using an RFLASH
            ! value of 500 mol/flash.  This is independent of path 
            ! length.  The overall final top-down scaling factor is not 
            ! applied here.  Since we over-predict the total global 
            ! flash rate slightly
            !
            !   OTD-LIS         :  45.9 flashes/sec; 
            !   GEOS-CHEM 4x5   :  68.2 flashes/sec; 
            !   GEOS-Chem 2x2.5 : 170.4 flashes/sec
            !
            ! an appropriate scaling factor is applied to the mid-
            ! latitudes boxes ( 45.9/68.2 or 45.9/170.4 ) so that we
            ! don't over-predict the amount of NOx released.  In 2004, 
            ! using just 500 mol/flash and no additional scaling, this 
            ! creates a MidLat LNOx contribution of 5.46 Tg N, and with 
            ! scaling (as in the implemented version), 3.68 Tg N.
            !
            !
            ! (6e) The total lightning is the sum of IC+CG paths:
            !   TOTAL = TOTAL_IC + TOTAL_CG
            !
            ! (6g) We then partition the NOx into each of the vertical 
            ! grid boxes within the column with a Ken Pickering PDF
            ! (see comments below).
            !
            ! (ltm, rch, bmy, 5/10/06, 3/27/07)
            !===========================================================

            !-----------------------------------------------------------
            ! (6a) Compute flash rate and apply OTD/LIS redistribution
            !-----------------------------------------------------------

            ! Convert [flashes/min] to [flashes/6h]
            RATE     = FLASHRATE * 360.0d0

!------------------------------------------------------------------------------
! Prior to 3/27/07:
!            ! Ratio of cloud-ground flashes to total # of flashes
!            X        = 1d0 / ( 1d0 + IC_CG_RATIO )
!
!            ! NOx [molec/6h] released in the IC, CG, and total pathways 
!            TOTAL_IC = RFLASH   * RATE * ( 1d0 - X ) * Z_IC * E_IC_CG
!            TOTAL_CG = RFLASH   * RATE *         X   * Z_CG
!            TOTAL    = TOTAL_IC + TOTAL_CG 
!------------------------------------------------------------------------------

            ! Get factors for OTD-LIS regional redistribution, OTD-LIS local
            ! redistribution, or no redistribution.  Redistribution makes sure 
            ! that the flashes appear in the proper place geographically.
            ! (ltm, bmy, 1/31/07)
            IF ( LOTDREG ) THEN
               REDIST = OTD_REG_REDIST(I,J)
            ELSE IF ( LOTDLOC ) THEN
               REDIST = OTD_LOC_REDIST(I,J)
            ELSE
               REDIST = 1d0
            ENDIF

            ! Apply regional or local OTD-LIS redistribution so that the 
            ! flashes occur in the right place. 
            RATE = RATE * REDIST

            !-----------------------------------------------------------
            ! (6b) Compute cloud-ground/total flash ratio
            !-----------------------------------------------------------

            ! Ratio of cloud-to-ground flashes to total # of flashes
            X    = 1d0 / ( 1d0 + IC_CG_RATIO )

            ! Compute LNOx emissions for tropics or midlats 

            IF ( XMID > EAST_WEST_DIV ) THEN 
               
               !--------------------------------------------------------
               ! (6c,6d) We are in EURASIA
               !--------------------------------------------------------
               IF ( YMID > EAST_NS_DIV ) THEN 

                  ! 6d: Eurasian Mid-Latitudes
                  TOTAL_IC = RFLASH_MIDLAT * RATE          * ( 1d0 - X )
                  TOTAL_IC = TOTAL_IC      * MID_LAT_SCALE

                  TOTAL_CG = RFLASH_MIDLAT * RATE          * X
                  TOTAL_CG = TOTAL_CG      * MID_LAT_SCALE

               ELSE                           

                  ! 6c: Eurasian Tropics
                  TOTAL_IC = RFLASH_TROPIC * RATE * ( 1d0 - X ) * Z_IC
                  TOTAL_CG = RFLASH_TROPIC * RATE * (       X ) * Z_CG

                  ! Apply top-down final global scale factor
                  IF ( LOTDREG ) THEN
                     TOTAL_IC = TOTAL_IC * FLASH_SCALE
                     TOTAL_CG = TOTAL_CG * FLASH_SCALE
                  ENDIF
               ENDIF


            ELSE   
               
               !--------------------------------------------------------
               ! (6c,6d) We are in the AMERICAS
               !--------------------------------------------------------
               IF ( YMID > WEST_NS_DIV ) THEN 

                  ! 6d: American Mid-Latitudes
                  TOTAL_IC = RFLASH_MIDLAT * RATE          * ( 1d0 - X )
                  TOTAL_IC = TOTAL_IC      * MID_LAT_SCALE

                  TOTAL_CG = RFLASH_MIDLAT * RATE          * X
                  TOTAL_CG = TOTAL_CG      * MID_LAT_SCALE

               ELSE                           

                  ! 6c: American Tropics
                  TOTAL_IC = RFLASH_TROPIC * RATE * ( 1d0 - X ) * Z_IC
                  TOTAL_CG = RFLASH_TROPIC * RATE * (       X ) * Z_CG

                  ! Apply top-down final global scale factor
                  IF ( LOTDREG ) THEN
                     TOTAL_IC = TOTAL_IC * FLASH_SCALE
                     TOTAL_CG = TOTAL_CG * FLASH_SCALE
                  ENDIF
               ENDIF
            ENDIF

            !-----------------------------------------------------------
            ! (6e) Compute total lightning
            !-----------------------------------------------------------

            ! Sum of IC + CG [molec/6h]
            TOTAL = TOTAL_IC + TOTAL_CG

!-----------------------------------------------------------------------------
! Prior to 3/27/07:            
!            TOTAL    = TOTAL * REDIST
!
!            !%%% NOTE: THIS FLASH_SCALE HAS BEEN DEVELOPED     %%%
!            !%%%       FOR THE OTD-LIS REGIONAL REDISTRIBUTION %%%
!            !%%%       YOU SHOULD COMMENT IT OUT FOR LOTDLOC   %%% 
!            !%%%       UNTIL WE HAVE A CHANCE TO DO MORE TESTS %%%
!            !%%%       (bmy, 2/1/07)                           %%%
!            ! Scale total lightning NOx to 6 Tg N/yr, accounting for
!            ! differences from met fields & resolution (ltm, bmy, 12/11/06)
!            IF ( LOTDREG ) THEN  !%%% BMY TEMP MODIFICATION
!            TOTAL    = TOTAL * FLASH_SCALE
!            ENDIF                !%%% BMY TEMP MODIFICATION
!------------------------------------------------------------------------------

            !-----------------------------------------------------------
            ! (6f) ND56 diagnostic: store flash rates [flashes/min/km2]
            !-----------------------------------------------------------
            IF ( ND56 > 0 .and. RATE > 0d0 ) THEN

               ! Lightning flashes per minute per km2
               RATE_SAVE   = ( FLASHRATE / A_KM2 ) * REDIST

               ! Store total, IC, and CG flash rates in AD56
               AD56(I,J,1) = AD56(I,J,1) +   RATE_SAVE
               AD56(I,J,2) = AD56(I,J,2) + ( RATE_SAVE * ( 1d0 - X ) )
               AD56(I,J,3) = AD56(I,J,3) + ( RATE_SAVE *         X   )

            ENDIF

            !-----------------------------------------------------------
            ! (6g) LIGHTDIST computes the lightning distribution from 
            ! the ground to the convective cloud top using cumulative
            ! distribution functions for ocean flashes, tropical land
            ! flashes, and non-tropical land flashes, as specified by
            ! Ken Pickering (1997).
            !-----------------------------------------------------------

            ! If there's lightning w/in the column ...
            IF ( TOTAL > 0d0 ) THEN

               ! Partition the column total NOx [molec/6h] from lightning 
               ! into the vertical using Pickering PDF functions
               CALL LIGHTDIST( I, J, LTOP, H0, YMID, TOTAL, VERTPROF )

               ! Add vertically partitioned NOx into SLBASE array
               DO L = 1, LLPAR
                  SLBASE(I,J,L) = SLBASE(I,J,L) + VERTPROF(L) 
               ENDDO
            ENDIF
         ENDDO
      ENDDO
!$OMP END PARALLEL DO

      ! Return to calling program
      END SUBROUTINE LIGHTNING_NL

!------------------------------------------------------------------------------

      SUBROUTINE LIGHTDIST( I, J, LTOP, H0, XLAT, TOTAL, VERTPROF )
!
!******************************************************************************
!  Subroutine LIGHTDIST reads in the CDF used to partition the 
!  column lightning NOx into the GEOS-CHEM vertical layers. 
!  (yhw, 1997; mje, ltm, bmy, 9/18/02, 12/11/06)
!
!  Arguments as Input:
!  ============================================================================
!  (1-2) I, J     (INTEGER) : (Lon,Lat) indices of the surface grid box
!  (3  ) LTOP     (INTEGER) : Level where convective cloud top is found
!  (4  ) H0       (REAL*8 ) : Convective cloud top height [m]
!  (5  ) XLAT     (REAL*8 ) : Latitude of surface grid box (I,J) [degrees]
!  (6  ) TOTAL    (REAL*8 ) : Total # of NOx molec. released from lightning
!  (7  ) VERTPROF (REAL*8 ) : Vertical profile of lightning emissions
!
!  References:
!  ============================================================================
!  (1 ) Pickering et al., JGR 103, 31,203 - 31,316, 1998.
!
!  NOTES:
!  (1 ) Use functions IS_LAND and IS_WATER to determine if the given grid
!        box is over land or water.  These functions work for all DAO met
!        field data sets. (bmy, 4/2/02)
!  (2 ) Renamed M2 to LTOP and THEIGHT to H0 for consistency w/ variable names
!        w/in "lightning.f".  Now read the "light_dist.dat.geos3" file for 
!        GEOS-3 directly from the DATA_DIR/lightning_NOx_200203/ subdirectory.
!        Now read the "light_dist.dat" file for GEOS-1, GEOS-STRAT directly 
!        from the DATA_DIR/lightning_NOx_200203/ subdirectory.  Added 
!        descriptive comment header.  Now trap I/O errors across all 
!        platforms with subroutine "ioerror.f".  Updated comments, cosmetic 
!        changes.  Redimension FRAC(NNLIGHT) to FRAC(LLPAR). (bmy, 4/2/02)
!  (3 ) Deleted obsolete code from April 2002.  Now reference IU_FILE and
!        IOERROR from "file_mod.f".  Now use IU_FILE instead of IUNIT as the
!        file unit number. (bmy, 6/27/02)
!  (4 ) Now reference BXHEIGHT from "dao_mod.f" (bmy, 9/18/02)
!  (5 ) Bug fix: add GEOS_4 to the #if block (bmy, 3/4/04)
!  (6 ) Now bundled into "lightning_mod.f".  CDF's are now read w/in
!        routine INIT_LIGHTNING to allow parallelization (bmy, 4/14/04)
!  (7 ) Now references DATA_DIR from "directory_mod.f" (bmy, 7/20/04)
!  (8 ) Now uses near-land formulation (ltm, bmy, 5/10/06)
!  (9 ) Added extra safety check for pathological boxes (bmy, 12/11/06)
!******************************************************************************
!
      ! References to F90 modules
      USE DAO_MOD,       ONLY : BXHEIGHT, IS_ICE,  IS_LAND
      USE DAO_MOD,       ONLY : IS_NEAR,  IS_WATER
      USE DIRECTORY_MOD, ONLY : DATA_DIR
      USE FILE_MOD,      ONLY : IU_FILE,  IOERROR

#     include "CMN_SIZE"   ! Size parameters

      ! Arguments
      INTEGER, INTENT(IN)  :: I,  J,    LTOP
      REAL*8,  INTENT(IN)  :: H0, XLAT, TOTAL
      REAL*8,  INTENT(OUT) :: VERTPROF(LLPAR)

      ! Local variables
      LOGICAL              :: ITS_NEAR_LAND
      INTEGER              :: M, MTYPE, L, III, IOS, IUNIT, JJJ
      REAL*8               :: ZHEIGHT
      REAL*8               :: FRAC(LLPAR)
      CHARACTER(LEN=255)   :: FILENAME

      !=================================================================
      ! LIGHTDIST begins here!
      !=================================================================

      ! Initialize 
      MTYPE    = 0
      VERTPROF = 0d0

      !=================================================================
      ! Test whether location (I,J) is continental, marine, or snow/ice
      !
      ! Depending on the combination of land/water and latitude, 
      ! assign a flag describing the type of lightning:
      !
      !   MTYPE = 1: ocean lightning
      !   MTYPE = 2: tropical continental lightning (from 30S to 30N)
      !   MTYPE = 3: midlatitude continental lightning (all other lats)
      !       
      ! Here, we are using the "near-land" criteria.  Grid boxes that:
      !
      !   (a) contain at least 20% land (25% for PRECON param), and/or
      !   (b) have a nearest-neighbor box that is a land box
      !
      ! are treated as if they were themselves land boxes.  Therefore, 
      ! the continental lightning flash rates will be applied to land 
      ! boxes PLUS those boxes which are located just offshore.
      !
      ! Also, there is no lightning over the polar regions, so we
      ! return with VERTPROF(:) = 0 if the box is mostly snow/ice.
      !
      ! (ltm, bmy, 5/10/06)
      !=================================================================

      ! Test for near-land and save w/in a variable
      ITS_NEAR_LAND = IS_NEAR( I, J, NL_THRESH, NL_NBOR )

      ! Test for land/water/ice
      IF ( ITS_NEAR_LAND ) THEN

         !------------------------------
         ! Land or Near-Land box
         !------------------------------
         IF ( ABS( XLAT ) <= 30 ) THEN

            ! Tropical continental lightning
            MTYPE = 2

         ELSE

            ! Midlatitude continental lightning
            MTYPE = 3

         ENDIF

      ELSE IF ( (       IS_WATER( I, J ) )  .and. 
     &          ( .not. IS_LAND(  I, J ) )  .and.
     &          ( .not. ITS_NEAR_LAND    ) ) THEN

         !------------------------------
         ! Ocean box (not near-land)
         !------------------------------
    
         ! Marine lightning
         MTYPE = 1

      ELSE IF ( IS_ICE( I, J ) ) THEN

         !------------------------------
         ! Snow/Ice box (e.g. at poles)
         !------------------------------

         ! Turn off lightning 
         RETURN

      ENDIF

      ! Extra safety check for pathological grid boxes (bmy, 11/29/06)
      IF ( MTYPE == 0 ) RETURN

      !=================================================================
      ! Use the CDF for this type of lightning to partition the total
      ! column lightning into the GEOS-3, GEOS-4, or GEOS-5 layers
      !=================================================================
      ZHEIGHT = 0.0

      ! Compute the height [km] at the top of each vertical level.
      ! Look up the cumulative fraction of NOx for each vertical level
      DO L = 1, LTOP
         ZHEIGHT = ZHEIGHT + BXHEIGHT(I,J,L)
         FRAC(L) = PROFILE( NINT( ( ZHEIGHT/H0 )*3200. ), MTYPE ) *0.01
      ENDDO

      ! Convert from cumulative fraction to fraction for each level
      DO L = LTOP, 2, - 1
         FRAC(L) = FRAC(L) - FRAC(L-1)
      ENDDO 
      
      ! Partition lightning NOx by layer into VERTPROF
      DO L = 1, LTOP
         VERTPROF(L) = ( FRAC(L) * TOTAL )
      ENDDO

      ! Return to calling program
      END SUBROUTINE LIGHTDIST

!------------------------------------------------------------------------------

      SUBROUTINE FLASHES_CTH( I, J, HEIGHT, FLASHRATE )
!
!******************************************************************************
!  Subroutine FLASHES_CTH determines the rate of lightning flashes per minute
!  based on the height of convective cloud tops, and the intra-cloud to 
!  cloud-ground strike ratio.  (ltm, bmy, 5/10/06, 12/11/06)
!
!  Arguments as Input:
!  ============================================================================
!  (1-2) I, J        : GEOS-Chem longitude & latitude indices
!  (3  ) HEIGHT      : Height of convective cloud tops [m]
! 
!  Arguments as Output:
!  ============================================================================
!  (4  ) FLASHRATE   : Lightning flash rate [flashes/minute]
!
!  NOTES:
!  (1  ) Subroutine renamed from FLASHES (ltm, bmy, 5/10/06)
!  (2  ) Remove CCTHICK, IC_CG_RATIO as arguments.  Remove computation of
!         IC_CG_RATIO and move that to GET_IC_CG_RATIO. (ltm, bmy, 12/11/06)
!******************************************************************************
! 
#     include "define.h"

      ! References to F90 Modules
      USE DAO_MOD, ONLY     : IS_ICE, IS_NEAR, IS_WATER

      ! Arguments
      INTEGER, INTENT(IN)  :: I, J
      REAL*8,  INTENT(IN)  :: HEIGHT
      REAL*8,  INTENT(OUT) :: FLASHRATE

      ! Local Variables
      LOGICAL              :: ITS_NEAR_LAND

      !================================================================
      ! FLASHES_CTH begins here!
      !
      ! COMPUTE LIGHTNING FLASH RATE / MINUTE
      !
      ! Price & Rind (1992) give the following parameterizations for
      ! lightning flash rates as a function of convective cloud top
      ! height [km]:
      !
      !    FLAND  = 3.44e-5 * ( CLDTOP HEIGHT [km] ^ 4.9  )
      !    FOCEAN = 6.4e-4  * ( CLDTOP HEIGHT [km] ^ 1.73 )
      !
      ! Lightning will therefore occur much more often on land.  It 
      ! goes as approx. the 5th power of height, as opposed to approx. 
      ! the 2nd power of height over oceans.
      !
      ! Here, we are using the "near-land" criteria.  Grid boxes that:
      !
      !   (a) contain at least 20% land, and/or
      !   (b) have a nearest-neighbor box that is a land box
      !
      ! are treated as if they were themseves land boxes.  Therefore, 
      ! the continental lightning flash rates will be applied to land 
      ! boxes PLUS to those boxes which are located just offshore.
      !
      ! We suppress lightning where the surface is mostly ice.  
      !
      ! (ltm, bmy, 5/10/06, 12/11/06)
      !================================================================

      ! Test if the box is a land box or a near-land box
      ITS_NEAR_LAND = IS_NEAR( I, J, NL_THRESH, NL_NBOR )
     
      ! Test for land type
      IF ( ITS_NEAR_LAND ) THEN

         ! Flashes/min over near-land boxes: treat as land
         FLASHRATE   = 3.44d-5 * ( ( HEIGHT * 1d-3 )**4.9d0  )

      ELSE IF ( IS_WATER( I, J ) .and.  ( .not. ITS_NEAR_LAND ) ) THEN

         ! Flashes/min over water (not near-land): treat as water
         FLASHRATE   = 6.4d-4  * ( ( HEIGHT * 1d-3 )**1.73d0 )

      ELSE IF ( IS_ICE( I, J ) ) THEN

         ! Suppress lightning over snow/ice
         FLASHRATE   = 0d0

      ENDIF

      ! Return to calling program
      END SUBROUTINE FLASHES_CTH

!------------------------------------------------------------------------------

      SUBROUTINE FLASHES_MFLUX( I, J, MFLUX, IC_CG_RATIO, FLASHRATE )
!
!******************************************************************************
!  Subroutine FLASHES_MFLUX determines the rate of lightning flashes per
!  minute, based on the upward cloud mass flux [kg m^-2 min^-1] at 0.44 sigma,
!  and the intra-cloud to cloud-ground strike ratio. 
!  (ltm, bmy, 5/10/06, 12/11/06)
!
!  Arguments as Input:
!  ============================================================================
!  (1-2) I, J        : GEOS-CHEM longitude & latitude indices
!  (3  ) HEIGHT      : Height of convective cloud tops [m]
!  (4  ) IC_CG_RATIO : Intra-cloud / cloud-ground flash ratio [unitless]
! 
!  Arguments as Output:
!  ============================================================================
!  (5  ) FLASHRATE   : Total lightning flash rate [flashes/minute]
!
!  NOTES:
!  (1 ) Remove CCTHICK as an argument.  Now change IC_CG_RATIO to an input
!        argument.  Remove computation of IC_CG_RATIO and move that to 
!        GET_IC_CG_RATIO. (ltm, bmy, 12/11/06)
!******************************************************************************
!
      ! References to F90 Modules
      USE DAO_MOD,     ONLY : IS_ICE
      USE GRID_MOD,    ONLY : GET_AREA_M2

      ! Arguments
      INTEGER, INTENT(IN)  :: I, J
      REAL*8,  INTENT(IN)  :: MFLUX
      REAL*8,  INTENT(IN)  :: IC_CG_RATIO
      REAL*8,  INTENT(OUT) :: FLASHRATE

      ! Local Variables
      REAL*8               :: F_CG, LF_CG, MF

      !=================================================================
      ! FLASHES_MFLUX begins here!
      !=================================================================       

      ! Test for land type
      IF ( IS_ICE( I, J ) ) THEN

         ! Suppress lightning near poles
         FLASHRATE   = 0d0

      ELSE

         !==============================================================
         ! (1) COMPUTE CLOUD-GROUND LIGHTNING FLASH RATE / MINUTE
         !
         ! Allen and Pickering (2002) give the following 
         ! parameterizations for lightning flash rates as a function 
         ! of upward cloud mass flux [kg m^-2 min^-1] at 0.44 sigma:
         !
         !    LF_CG = [delta x][delta y] *
         !            ( a + b*M + c*M^2 + d*M^3 + e*M^4 ) / A
         !
         !    For: 0 < M < 9.6 [km/m2/min]
         !
         ! Where:
         !    (1) LF_CG is the CG flash rate [flashes/min)] within the
         !         2.0 x 2.5 grid box 
         !    (2) a, b, c, d, e are coefficients, listed below
         !    (3) [delta x][delta y] is the area of the grid box
         !    (4) A is the area of a 2.0 x 2.5 box centered at 30N
         !    (5) M is the upward cloud mass flux at 0.44 sigma
         !        
         ! Since the polynomial experiences an inflection at 
         ! M ~= 9.6 [km/m2/min], points greater than this are 
         ! set to 9.6 [km/m2/min].
         ! 
         ! The polynomial coefficients are:
         !    a=-2.34e-2, b=3.08e-1, c=-7.19e-1, d=5.23e-1, e=-3.71e-2
         !
         ! NOTE: LF_CG is the cloud-ground flash rate.
         !==============================================================

         ! Cap mass flux at 9.6 [km/m2/min]
         MF = MIN( MFLUX, 9.6d0 )

         ! First make the polynomial
         LF_CG = -2.34d-02 + MF * ( -3.71d-02 +
     &                       MF * (  5.23d-01 +
     &                       MF * ( -7.19d-01 +
     &                       MF * (  3.08d-01 ) ) ) )

         ! Now normalize it by the area of the box at 30N
         LF_CG = LF_CG * ( GET_AREA_M2( J ) / AREA_30N )
         
         !==============================================================
         ! (2) COMPUTE TOTAL FLASHRATE FROM IC/CG RATIO
         !==============================================================

         ! Cloud-ground flash rate [flashes/min]
	 F_CG        = 1d0 / ( 1d0 + IC_CG_RATIO )

	 ! Divide the CG flash rate by the fraction of CG/total flashes
         ! to get the total flash rate in [flashes/min]
         FLASHRATE   = LF_CG / F_CG
         
      ENDIF

      ! Return to calling program
      END SUBROUTINE FLASHES_MFLUX

!-----------------------------------------------------------------------------

      SUBROUTINE FLASHES_PRECON( I, J, RAIN, IC_CG_RATIO, FLASHRATE )
!
!****************************************************************************
!  Subroutine FLASHES_PRECON determines the rate of lightning flashes per
!  minute, based on the rate of surface-level convective precipitation, 
!  and the intra-cloud to cloud-ground strike ratio.  
!  (ltm, bmy, 5/10/06, 12/11/06)
!
!  Arguments as Input:
!  ============================================================================
!  (1-2) I, J        : GEOS-CHEM longitude & latitude indices
!  (3  ) HEIGHT      : Height of convective cloud tops [m]
!  (4  ) IC_CG_RATIO : Inter-Cloud (IC) flashes / Cloud-Ground (CG) flashes
! 
!  Arguments as Output:
!  ============================================================================
!  (5  ) FLASHRATE   : Total lightning flash rate [flashes/minute]
!
!  NOTES:
!  (1 ) Remove CCTHICK as an argument.  Now change IC_CG_RATIO to an input
!        argument.  Remove computation of IC_CG_RATIO and move that to 
!        GET_IC_CG_RATIO. (ltm, bmy, 12/11/06)
!******************************************************************************
!
      ! References to F90 Modules
      USE DAO_MOD,     ONLY : IS_NEAR, IS_ICE, IS_WATER
      USE GRID_MOD,    ONLY : GET_AREA_M2

      ! Arguments
      INTEGER, INTENT(IN)  :: I, J
      REAL*8,  INTENT(IN)  :: RAIN
      REAL*8,  INTENT(IN)  :: IC_CG_RATIO
      REAL*8,  INTENT(OUT) :: FLASHRATE

      ! Local Variables
      LOGICAL              :: ITS_NEAR_LAND 
      REAL*8               :: F_CG, LF_CG, PR

      !=================================================================
      ! FLASHES_PRECON begins here!
      !
      ! (1) COMPUTE CLOUD-GROUND LIGHTNING FLASH RATE / MINUTE
      !
      ! Allen and Pickering (2002) give the following parameterizations 
      ! for CG lightning flash rates as a function of surface 
      ! convective precipitation [mm d^-1] during the 6-hr period:
      !
      !    LF_CG = [delta x][delta y] *
      !            ( a + b*P + c*P^2 + d*P^3 + e*P^4 ) /A,
      !                                           
      !    For: 7 < P < 90 [mm/day]
      !       
      ! Where:
      !    (1) LF_CG = CG flash rate (flashes/min) w/in the grid box
      !    (2) a, b, c, d, e are coefficients, listed below
      !    (3) [delta x][delta y] is the area of the grid box
      !    (4) A is the area of a grid box centered at 30N
      !    (5) P is the PRECON rate [mm/day] during the 6-hour period.
      ! 
      ! Land equation for boxes that are greater than 25% land.
      ! Water equation for boxes that are less than 25% land.
      !
      ! Here, we are using the "near-land" criteria.  Grid boxes that:
      !
      !   (a) contain at least 25% land, and/or
      !   (b) have a nearest-neighbor box that is a land box
      !
      ! are treated as if they were themseves land boxes.  Therefore, 
      ! the continental lightning flash rates will be applied to land 
      ! boxes PLUS to those boxes which are located just offshore.
      !
      ! The polynomial coefficients for land boxes are:
      !   a=3.75e-02, b=-4.76e-02, c=5.41e-03, d=3.21e-04, e=-2.93e-06
      !
      ! and the polynomial coefficients for water boxes are:
      !   a=5.23e-02, b=-4.80e-02, c=5.45e-03, d=3.68e-05, e=-2.42e-07
      !
      ! Both polynomials give slightly negative values for small precip
      ! rates. In addition, the land polynomial has an inflection point 
      ! at ~90 [mm/day]. Therefore flash rates are set to 0 for precip
      ! rates of less than 7 [mm/day] and to the value at 90 [mm/day]
      ! precipitation rates exceeding 90 [mm/day].
      !=================================================================

      ! Make sure PR is w/in 7-90 [mm/day]
      IF ( RAIN > 90.0d0 ) THEN
         PR = 90.0d0
      ELSE IF ( RAIN < 7.0d0 ) THEN
         PR = 7.0d0
      ELSE
         PR = RAIN
      ENDIF

      ! Test if the box is a land box or a near-land box
      ITS_NEAR_LAND = IS_NEAR( I, J, NL_THRESH, NL_NBOR )

      ! Test for land type
      IF ( ITS_NEAR_LAND ) THEN

         !---------------------------
         ! Land or near-land box
         !---------------------------

         ! First make the polynomial
         LF_CG = 3.75d-02 + PR * ( -4.76d-02 +
     &                      PR * (  5.41d-03 +
     &                      PR * (  3.21d-04 +
     &                      PR * ( -2.93d-06 ) ) ) )

         ! Then normalize it by the area the box at 30N
         LF_CG = LF_CG * ( GET_AREA_M2( J ) / AREA_30N )

      ELSE IF ( IS_WATER( I, J ) .and. ( .not. ITS_NEAR_LAND ) ) THEN

         !---------------------------
         ! Water (not near-land) box
         !---------------------------

         ! First make the polynomial
         LF_CG = 5.23d-02 + PR * ( -4.80d-02 +
     &                      PR * (  5.45d-03 +
     &                      PR * (  3.68d-05 +
     &                      PR * ( -2.42d-07 ) ) ) )

         ! Then normalize it by the area the box at 30N
         LF_CG = LF_CG * ( GET_AREA_M2( J ) / AREA_30N )

      ELSE IF ( IS_ICE( I, J ) ) THEN

         !---------------------------
         ! Snow/ice box (e.g. poles)
         !---------------------------

         ! Suppress lightning over poles
         FLASHRATE   = 0d0

      ENDIF

      !=================================================================
      ! (2) COMPUTE TOTAL FLASHRATE FROM IC/CG RATIO
      !=================================================================

      ! Cloud-ground flash rate [flashes/min]
      F_CG        = 1d0 / ( 1d0 + IC_CG_RATIO )

      ! Divide the CG flash rate by the fraction of CG/total flashes
      ! to get the total flash rate in [flashes/min]
      FLASHRATE   = LF_CG / F_CG

      ! Return to calling program
      END SUBROUTINE FLASHES_PRECON

!------------------------------------------------------------------------------

      FUNCTION GET_IC_CG_RATIO( CCTHICK ) RESULT( IC_CG_RATIO )
!
!******************************************************************************
!  Function GET_IC_CG_RATIO calculates the Intra-Cloud (IC) and Cloud-to-
!  Ground (CG) lightning flash ratio based on the method of Price and Rind 
!  1993, which is calculated from the cold-cloud depth (CCTHICK).
!  (ltm, bmy, 12/11/06)
!
!  Arguments as Input:
!  ============================================================================
!  (1 ) CCTHICK     (REAL*8) : Cold-Cloud Thickness [m]
! 
!  Arguments as Output:
!  ============================================================================
!  (2 ) IC_CG_RATIO (REAL*8) : IC / CG flash ratio  [unitless]
!
!  NOTES:
!  (1 ) Split off from FLASHES_CTH, FLASHES_MFLUX, FLASHES_PRECON into this
!        separate function (ltm, bmy, 12/11/06)
!******************************************************************************
!
      ! Arguments
      REAL*8,  INTENT(IN)  :: CCTHICK

      ! Local Variables
      REAL*8               :: CC, F_CG

      ! Function value
      REAL*8               :: IC_CG_RATIO

      !=================================================================
      ! GET_IC_CG_RATIO begins here!
      !
      ! COMPUTE INTRA-CLOUD / CLOUD-GROUND FLASH RATIO 
      !
      ! Price & Rind (1993) compute the ratio of Cloud-Ground 
      ! to Total Flashes by the parameterization:
      !
      ! For 5.5 < dz < 14:
      !
      !     f_CG = 1 / (( A*dz^4 + B*dz^3 + C*dz^2 + D*dz + E ) + 1 )
      !
      ! For dz > 14:
      !
      !     f_CG = 0.02
      !                                        
      ! Where:
      !
      ! (1) dz is the depth [km] of the cloud above the freezing 
      !     level.  The cold-cloud thickness (dz) is the depth of 
      !     the layer between the cloud top and the center of the 
      !     highest layer for which the temperature exceeds 273 K. 
      !     The cold-cloud thickness is set to 5.5 km at grid points 
      !     where it is less than 5.5 km.
      !
      ! (2) The polynomial coefficients are:
      !        A=0.021,  B=-0.648,  C=7.493,  D=-36.54,  E=63.09
      !
      ! 
      ! Note: f_IC = 1 - f_CG
      ! 
      ! And hence,
      !
      !     IC_CG_RATIO = ( 1 - f_CG ) / f_CG
      !
      !
      ! IC_CG_RATIO is passed back to routine the LIGHTNING_NL, where
      ! it is passed to FLASHES_MFLUX and FLASHES_PRECON.  In these
      ! routines, the fraction of total lightning flashes that are 
      ! cloud-ground (CG) flashes is computed by:
      ! 
      !     F_CG        = 1d0 / ( 1d0 + IC_CG_RATIO )
      !
      ! and the fraction of the total lightning flashes that are
      ! intra-cloud (IC) flashes is computed by:
      !
      !     F_IC        = 1d0 - 1d0 / ( 1d0 + IC_CG_RATIO )
      !=====================================================================

      ! Convert cold cloud thickness from [m] to [km] (min value: 5.5 km)
      CC = MAX( CCTHICK * 1d-3, 5.5 )

      ! Compute cloud-ground flash ratio as described above
      IF ( CC > 14d0 ) THEN

         ! Constant value above 14 km
         F_CG = 0.02d0

      ELSE

         ! First create the polynomial expression
         F_CG = 63.09d0 + CC * ( -36.54d0  +
     &                    CC * (   7.493d0 + 
     &                    CC * (  -0.648d0 +
     &                    CC * (   0.021d0 ) ) ) )

         ! Then put it in the denominator
         F_CG = 1d0 / ( F_CG + 1d0 )
                  
      ENDIF

      ! Intra-Cloud / Cloud-Ground flash ratio
      IC_CG_RATIO = ( 1d0 - F_CG ) / F_CG

      ! Return to calling program
      END FUNCTION GET_IC_CG_RATIO

!------------------------------------------------------------------------------

      SUBROUTINE READ_REGIONAL_REDIST( MONTH )
!
!******************************************************************************
!  Subroutine READ_REGIONAL_REDIST reads in monthly factors in order to 
!  redistribute GEOS-Chem flash rates according the OTD-LIS climatological 
!  regional redistribution method. (ltm, bmy, 5/10/06, 2/22/07)
!
!  Arguments as Input:
!  ============================================================================
!  (1 ) MONTH (INTEGER) : Current month (1-12)
!
!  NOTES:
!  (1 ) Change CTH filename from "v0" to "v2". Renamed to READ_REGIONAL_REDIST.
!        (lth, bmy, 2/22/07)
!******************************************************************************
!
      ! References to F90 modules
      USE BPCH2_MOD,     ONLY : GET_NAME_EXT, GET_RES_EXT
      USE BPCH2_MOD,     ONLY : GET_TAU0,     READ_BPCH2
      USE DIRECTORY_MOD, ONLY : DATA_DIR
      USE ERROR_MOD,     ONLY : ALLOC_ERR
      USE LOGICAL_MOD,   ONLY : LCTH,         LMFLUX,     LPRECON
      USE TRANSFER_MOD,  ONLY : TRANSFER_2D

#     include "CMN_SIZE"      ! Size parameters

      INTEGER, INTENT(IN)    :: MONTH

      ! Local variables
      REAL*4                 :: ARRAY(IGLOB,JGLOB,1)
      REAL*8                 :: TAU0
      CHARACTER(LEN=255)     :: FILENAME

      !=================================================================
      ! READ_OTD_LIS_REDIST begins here!
      !=================================================================

      ! Get file name
      IF ( LCTH ) THEN

         ! OTD-LIS regional file for CTH parameterization
         FILENAME = 'OTD-LIS-Regional-Redist.CTH.v2.'   // 
     &               GET_NAME_EXT() // '.' // GET_RES_EXT()

      ELSE IF ( LMFLUX ) THEN

         ! OTD-LIS regional file for MFLUX parameterization
         FILENAME = 'OTD-LIS-Regional-Redist.MFLUX.v1.'  // 
     &               GET_NAME_EXT() // '.' // GET_RES_EXT()

      ELSE IF ( LPRECON ) THEN

         ! OTD-LIS regional file for PRECON parameterization
         FILENAME = 'OTD-LIS-Regional-Redist.PRECON.v1.' // 
     &               GET_NAME_EXT() // '.' // GET_RES_EXT()

      ENDIF
      
      ! Prefix directory to file name
      FILENAME = TRIM( DATA_DIR )        // 
     &           'lightning_NOx_200605/' // TRIM( FILENAME ) 

      ! Echo info
      WRITE( 6, 100 ) TRIM( FILENAME )
 100  FORMAT( '     - READ_REGIONAL_REDIST: Reading ', a )

      ! Use "generic" year 1985 for time indexing
      TAU0 = GET_TAU0( MONTH, 1, 1985 ) 

      ! Read data
      CALL READ_BPCH2( FILENAME, 'OTD-REG',  1, 
     &                 TAU0,      IGLOB,     JGLOB,     
     &                 1,         ARRAY,     QUIET=.TRUE. )  

      ! Cast to REAL*8 and resize if necessary
      CALL TRANSFER_2D( ARRAY(:,:,1), OTD_REG_REDIST )

      ! Return to calling program 
      END SUBROUTINE READ_REGIONAL_REDIST

!------------------------------------------------------------------------------

      SUBROUTINE READ_LOCAL_REDIST( SEASON )
!
!******************************************************************************
!  Subroutine READ_LOCAL_REDIST reads in seasonal factors in order to 
!  redistribute GEOS-Chem flash rates according the "local redistribution"
!  method of Bastien Sauvage.  This helps to make sure that the lightning
!  flashes occur according to the distribution of observed convection.
!  (bastien, bmy, 1/26/07)
!
!  Arguments as Input:
!  ============================================================================
!  (1 ) SEASON (INTEGER) : Current season (1=DJF, 2=MAM, 3=JJA, 4=SON)
!
!  NOTES:
!******************************************************************************
!
      ! References to F90 modules
      USE BPCH2_MOD,     ONLY : GET_NAME_EXT, GET_RES_EXT
      USE BPCH2_MOD,     ONLY : GET_TAU0,     READ_BPCH2
      USE DIRECTORY_MOD, ONLY : DATA_DIR
      USE ERROR_MOD,     ONLY : ALLOC_ERR
      USE LOGICAL_MOD,   ONLY : LCTH,         LMFLUX,     LPRECON
      USE TRANSFER_MOD,  ONLY : TRANSFER_2D

#     include "CMN_SIZE"      ! Size parameters

      INTEGER, INTENT(IN)    :: SEASON

      ! Local variables
      REAL*4                 :: ARRAY(IGLOB,JGLOB,1)
      REAL*8                 :: TAU0
      CHARACTER(LEN=255)     :: FILENAME

      !=================================================================
      ! READ_LOCAL_REDIST begins here!
      !=================================================================

      ! Get file name
      IF ( LCTH ) THEN

         ! OTD-LIS Local file for CTH parameterization
         FILENAME = 'OTD-LIS-Local-Redist.CTH.v1.' // 
     &               GET_NAME_EXT() // '.'  // GET_RES_EXT()

      ELSE IF ( LMFLUX ) THEN

         ! OTD-LIS Local file for MFLUX parameterization
         FILENAME = 'OTD-LIS-Local-Redist.MFLUX.v1.'  // 
     &               GET_NAME_EXT() // '.' // GET_RES_EXT()

      ELSE IF ( LPRECON ) THEN

         ! OTD-LIS local file for PRECON parameterization
         FILENAME = 'OTD-LIS-Local-Redist.PRECON.v1.' // 
     &               GET_NAME_EXT() // '.' // GET_RES_EXT()

      ENDIF
      
      ! Prefix directory to file name
      FILENAME = TRIM( DATA_DIR )        // 
     &           'lightning_NOx_200605/' // TRIM( FILENAME ) 

      ! Echo info
      WRITE( 6, 100 ) TRIM( FILENAME )
 100  FORMAT( '     - READ_LOCAL_REDIST: Reading ', a )

      ! Get TAU0 depending on the season (generic year 1985)
      SELECT CASE( SEASON )
         CASE( 1 )
            TAU0 = -744d0
         CASE( 2 )
            TAU0 = 1416d0
         CASE( 3 )
            TAU0 = 3624d0
         CASE( 4 )
            TAU0 = 5832d0
      END SELECT

      ! Read data
      CALL READ_BPCH2( FILENAME, 'OTD-LOC',  1, 
     &                 TAU0,      IGLOB,     JGLOB,     
     &                 1,         ARRAY,     QUIET=.TRUE. )  
   
      ! Cast to REAL*8 and resize if necessary
      CALL TRANSFER_2D( ARRAY(:,:,1), OTD_LOC_REDIST )

      ! Return to calling program 
      END SUBROUTINE READ_LOCAL_REDIST

!------------------------------------------------------------------------------

      SUBROUTINE EMLIGHTNING_NL( I, J )
!
!******************************************************************************
!  Subroutine EMLIGHTNING_NL converts lightning emissions to [molec/cm3/s]
!  and stores them in the GEMISNOX array, which gets passed to SMVGEAR.
!  (bmy, 10/9/97, 4/14/04)
!  
!  NOTES:
!  (1 ) Remove IOFF, JOFF from the argument list.  Also remove references
!        to header files "CMN_O3" and "comtrid.h" (bmy, 3/16/00)
!  (2 ) Now use allocatable array for ND32 diagnostic (bmy, 3/16/00)  
!  (3 ) Now reference BXHEIGHT from "dao_mod.f".  Updated comments, cosmetic
!        changes.  Replace LCONVM with the parameter LLCONVM. (bmy, 9/18/02)
!  (4 ) Removed obsolete reference to "CMN".  Now bundled into 
!        "lightning_mod.f" (bmy, 4/14/04)
!******************************************************************************
!
      ! References to F90 modules
      USE DAO_MOD,  ONLY : BXHEIGHT
      USE DIAG_MOD, ONLY : AD32_li

#     include "CMN_SIZE"  ! Size parameters
#     include "CMN_DIAG"  ! ND32
#     include "CMN_NOX"   ! GEMISNOX

      ! Arguments
      INTEGER, INTENT(IN) :: I, J

      ! Local variables
      INTEGER             :: L
      REAL*8              :: TMP

      ! External functions
      REAL*8, EXTERNAL    :: BOXVL

      !=================================================================
      ! EMLIGHTNING_NL begins here!
      !=================================================================
      DO L = 1, LLCONVM 

          ! SLBASE(I,J,L) has units [molec NOx/6h/box], convert units:
          ! [molec/6h/box] * [6h/21600s] * [box/BOXVL cm3] = [molec/cm3/s]
          TMP             = SLBASE(I,J,L) / ( 21600.d0 * BOXVL(I,J,L) )
          GEMISNOX(I,J,L) = GEMISNOX(I,J,L) + TMP

          ! ND32 Diagnostic: Lightning NOx [molec NOx/cm2/s]
          IF ( ND32 > 0 ) THEN
             AD32_li(I,J,L) = AD32_li(I,J,L) + 
     &                        ( TMP * BXHEIGHT(I,J,L) * 1d2 )
          ENDIF
      ENDDO

      ! Return to calling program
      END SUBROUTINE EMLIGHTNING_NL

!------------------------------------------------------------------------------

      FUNCTION GET_FLASH_SCALE_CTH() RESULT( SCALE )
!
!******************************************************************************
!  Function GET_FLASH_SCALE_CTH (ltm, bmy, 2/22/07) returns a met-field 
!  dependent scale factor (for the CTH parameterization) which is to be 
!  applied to the lightning NOx emissions in order to bring the total to a 
!  specified value of 6 Tg N/yr.  
!
!  NOTES:
!******************************************************************************
!
#     include "define.h"

      ! Local variables
      REAL*8 :: SCALE
	  
      !=================================================================
      ! GET_FLASH_SCALE_CTH begins here!
      !=================================================================

#if   defined( GCAP )

      ! Needs defining
      SCALE = 1d0

#elif defined( GEOS_4 ) && defined( GRID4x5 ) 

      !%%% NOTE: This SCALE was computed for OTD-LIS regional redist %%%
      ! GEOS-4 4x5 1995-2005 produces a total of 73.3724 Tg N without
      ! any further scaling.  This results in an average of 6.67022 Tg N/yr.
      ! Scale the average down to 6 Tg N/yr. (ltm, bmy, 2/22/07)
      SCALE = 6.0d0 / 6.67022d0

#elif defined( GEOS_4 ) && defined( GRID2x25 )

      !%%% NOTE: This SCALE was computed for OTD-LIS regional redist %%%
      ! GEOS-4 2x2.5 1995-2005 produces a total of 179.224 Tg N without
      ! any further scaling.  This results in an average of 16.2931 Tg N/yr.
      ! Scale the average down to 6 Tg N/yr. (ltm, bmy, 2/22/07)
      SCALE = 6.0d0 / 16.2931d0
	  
#elif defined( GEOS_4 ) && defined( GRID1x125 )

      ! Needs defining
      SCALE = 1.0d0
	  
#elif defined( GEOS_3 ) && defined( GRID4x5 )

      ! Needs defining
      SCALE = 1.0d0
	  	 
#elif defined( GEOS_3 ) && defined( GRID2x25 )

      ! Needs defining
      SCALE = 1.0d0
	  
#elif defined( GEOS_3 ) && defined( GRID1x1 ) && defined( NESTED_CH )

      ! Needs defining
      SCALE = 1.0d0
	  
#elif defined( GEOS_3 ) && defined( GRID1x1 ) && defined( NESTED_NA )

      ! Needs defining
      SCALE = 1.0d0

#endif

      ! Return to calling program
      END FUNCTION GET_FLASH_SCALE_CTH

!------------------------------------------------------------------------------

      FUNCTION GET_FLASH_SCALE_MFLUX() RESULT( SCALE )
!
!******************************************************************************
!  Function GET_FLASH_SCALE_MFLUX (ltm, bmy, 12/11/06) returns a met-field 
!  dependent scale factor (for the MFLUX parameterization) which is to be 
!  applied to the lightning NOx emissions in order to bring the total to a 
!  specified value of 6 Tg N/yr.  
!
!  NOTES: FACTORS YET TO BE DETERMINED
!******************************************************************************
!
#     include "define.h"

      ! Local variables
      REAL*8 :: SCALE
	  
      !=================================================================
      ! GET_FLASH_SCALE_MFLUX begins here!
      !=================================================================

#if   defined( GCAP )

      ! Needs defining
      SCALE = 1.0d0

#elif defined( GEOS_4 ) && defined( GRID4x5 ) 

      ! Needs defining
      SCALE = 1.0d0

#elif defined( GEOS_4 ) && defined( GRID2x25 )

      ! Needs defining
      SCALE = 1.0d0
	  
#elif defined( GEOS_4 ) && defined( GRID1x125 )

      ! Needs defining
      SCALE = 1.0d0
	  
#elif defined( GEOS_3 ) && defined( GRID4x5 )

      ! Needs defining
      SCALE = 1.0d0
	  	  
#elif defined( GEOS_3 ) && defined( GRID2x25 )

      ! Needs defining
      SCALE = 1.0d0
	  
#elif defined( GEOS_3 ) && defined( GRID1x1 ) && defined( NESTED_CH )

      ! Needs defining
      SCALE = 1.0d0
	  
#elif defined( GEOS_3 ) && defined( GRID1x1 ) && defined( NESTED_NA )

      ! Needs defining
      SCALE = 1.0d0

#endif

      ! Return to calling program
      END FUNCTION GET_FLASH_SCALE_MFLUX

!------------------------------------------------------------------------------

      FUNCTION GET_FLASH_SCALE_PRECON() RESULT( SCALE )
!
!******************************************************************************
!  Function GET_FLASH_SCALE_PRECON (ltm, bmy, 12/11/06) returns a met-field 
!  dependent scale factor (for the PRECON parameterization) which is to be 
!  applied to the lightning NOx emissions in order to bring the total to a 
!  specified value of 6 Tg N/yr.  
!
!  NOTES: FACTORS YET TO BE DETERMINED
!******************************************************************************
!
#     include "define.h"

      ! Local variables
      REAL*8 :: SCALE
	  
      !=================================================================
      ! GET_FLASH_SCALE_PRECON begins here!
      !=================================================================

#if   defined( GCAP )

      ! Needs defining
      SCALE = 1.0d0

#elif defined( GEOS_4 ) && defined( GRID4x5 ) 

      ! Needs defining
      SCALE = 1.0d0

#elif defined( GEOS_4 ) && defined( GRID2x25 )

      ! Needs defining
      SCALE = 1.0d0
	  
#elif defined( GEOS_4 ) && defined( GRID1x125 )

      ! Needs defining
      SCALE = 1.0d0
	  
#elif defined( GEOS_3 ) && defined( GRID4x5 )

      ! Needs defining
      SCALE = 1.0d0
	  	  
#elif defined( GEOS_3 ) && defined( GRID2x25 )

      ! Needs defining
      SCALE = 1.0d0
	  
#elif defined( GEOS_3 ) && defined( GRID1x1 ) && defined( NESTED_CH )

      ! Needs defining
      SCALE = 1.0d0
	  
#elif defined( GEOS_3 ) && defined( GRID1x1 ) && defined( NESTED_NA )

      ! Needs defining
      SCALE = 1.0d0

#endif

      ! Return to calling program
      END FUNCTION GET_FLASH_SCALE_PRECON

!------------------------------------------------------------------------------

      SUBROUTINE INIT_LIGHTNING_NOX_NL
!
!******************************************************************************
!  Subroutine INIT_LIGHTNING_NOX_NL allocates all module arrays.  It also 
!  reads the lightning CDF data from disk before the first lightning timestep. 
!  (bmy, 4/14/04, 1/31/07)
!
!  NOTES:
!  (1 ) Now reference DATA_DIR from "directory_mod.f"
!  (2 ) Now call GET_MET_FIELD_SCALE to initialize the scale factor for
!        each met field type and grid resolution (bmy, 8/25/05)
!  (3 ) Now make sure all USE statements are USE, ONLY (bmy, 10/3/05)
!  (4 ) Now get the box area at 30N for MFLUX, PRECON (lth, bmy, 5/10/06)
!  (5 ) Rename OTDSCALE to OTD_REG_REDIST.  Also add similar array 
!        OTD_LOC_REDIST.  Now call GET_FLASH_SCALE_CTH, GET_FLASH_SCALE_MFLUX,
!        GET_FLASH_SCALE_PRECON depending on the type of lightning param used.
!        Updated comments.  (ltm, bmy, 1/31/07)
!******************************************************************************
!
      ! References to F90 modules
      USE DIRECTORY_MOD, ONLY : DATA_DIR
      USE ERROR_MOD,     ONLY : ALLOC_ERR
      USE FILE_MOD,      ONLY : IOERROR,   IU_FILE
      USE GRID_MOD,      ONLY : GET_YEDGE, GET_AREA_M2
      USE LOGICAL_MOD,   ONLY : LCTH,      LMFLUX
      USE LOGICAL_MOD,   ONLY : LPRECON,   LOTDLOC,   LOTDREG

#     include "CMN_SIZE"      ! Size parameters
  
      ! Local variables
      INTEGER                :: AS, III, IOS, JJJ
      REAL*8                 :: Y0, Y1
      CHARACTER(LEN=255)     :: FILENAME

      !=================================================================
      ! INIT_LIGHTNING_NOX begins here!
      !=================================================================

      !------------------
      ! Define variables
      !------------------

      ! Get overall scaling factor.  Dependent on grid resolution and
      ! parameterization type, will return an appropriate value for 
      ! FLASH_SCALE that will the total amount of LNOx to our best 
      ! estimate of 6 Tg N/yr. (ltm, bmy, 12/11/06)
      IF ( LCTH ) THEN
         FLASH_SCALE = GET_FLASH_SCALE_CTH()
      ELSE IF ( LMFLUX ) THEN
         FLASH_SCALE = GET_FLASH_SCALE_MFLUX()
      ELSE IF ( LPRECON ) THEN
         FLASH_SCALE = GET_FLASH_SCALE_PRECON()
      ENDIF

      ! NNLIGHT is the number of points for the lightning PDF's
      NNLIGHT = 3200

      ! Set the threshold and # of neighbor boxes to search for the 
      ! near-land criterion in function IS_NEAR (ltm, bmy, 5/10/06)
      IF ( LPRECON ) THEN
         NL_THRESH = 0.25d0
         NL_NBOR   = 1
      ELSE
         NL_THRESH = 0.20d0
         NL_NBOR   = 1
      ENDIF

      ! Find area of box centered at 30N.  This is necessary for the 
      ! PRECON and MFLUX parameterizations, which are normalized to a 
      ! box this size in the literature. (ltm, bmy, 5/10/06)
      IF ( LMFLUX .or. LPRECON ) THEN
       
         ! Loop over latitudes
         DO JJJ = 1, JJPAR             
                                
            ! S and N latitude edges of grid box [degrees]
            Y0 = GET_YEDGE( JJJ   )
            Y1 = GET_YEDGE( JJJ+1 )

            ! Test if the box center spans 30N
            IF ( Y0 <= 30d0 .and. Y1 >= 30d0 ) THEN

               ! Grid box surface area [m2] 
               AREA_30N = GET_AREA_M2( JJJ )

               ! Break out of loop
               EXIT
            ENDIF
         ENDDO
      ENDIF

      !-----------------
      ! Allocate arrays
      !-----------------

      ! Allocate PROFILE
      ALLOCATE( PROFILE( NNLIGHT, NLTYPE ), STAT=AS )
      IF ( AS /= 0 ) CALL ALLOC_ERR( 'PROFILE' )
      PROFILE = 0d0

      ! Allocate SLBASE
      ALLOCATE( SLBASE( IIPAR, JJPAR, LLPAR ), STAT=AS )
      IF ( AS /= 0 ) CALL ALLOC_ERR( 'SLBASE' )
      SLBASE = 0d0

      IF ( LOTDREG ) THEN

         ! Array for OTD-LIS regional redistribution factors
         ALLOCATE( OTD_REG_REDIST( IIPAR, JJPAR ), STAT=AS )
         IF ( AS /= 0 ) CALL ALLOC_ERR( 'OTD_REG_REDIST' )
         OTD_REG_REDIST = 0d0

      ELSE IF ( LOTDLOC ) THEN

         ! Array for OTD-LIS local redistribution factors
         ALLOCATE( OTD_LOC_REDIST( IIPAR, JJPAR ), STAT=AS )
         IF ( AS /= 0 ) CALL ALLOC_ERR( 'OTD_LOC_REDIST' )
         OTD_LOC_REDIST = 0d0

      ENDIF

      !=================================================================
      ! Read lightning CDF for GEOS-3, GEOS-4, GEOS-5, GCAP met data
      ! 
      ! NOTE: Since some of these vertical grids have a fine vertical
      ! resolution near the surface, we had to interpolate Ken
      ! Pickering CDF's to a much finer mesh, with 3200 points instead 
      ! of 100.  This was done by Mat Evans.  The vertical resolution
      ! of the CDF's in the file read in below is 0.05 km. 
      !=================================================================

      ! Define filename for GEOS-3 CDF file
      FILENAME = TRIM( DATA_DIR ) // 
     &           'lightning_NOx_200605/light_dist.dat.geos345.gcap'        

      ! Echo info
      WRITE( 6, 100 ) TRIM( FILENAME )
 100  FORMAT( '     - INIT_LIGHTNING: Reading ', a )
      
      ! Open file containing lightning PDF data
      OPEN( IU_FILE, FILE=TRIM( FILENAM E), STATUS='OLD', IOSTAT=IOS )
      IF ( IOS /= 0 ) CALL IOERROR( IOS, IU_FILE, 'lightdist:1' )
         
      ! Read 12 header lines
      DO III = 1, 12
         READ( IU_FILE, '(a)', IOSTAT=IOS ) 
         IF ( IOS /= 0 ) CALL IOERROR( IOS, IU_FILE, 'lightdist:2' )
      ENDDO
         
      ! Read NNLIGHT types of lightning profiles
      DO III = 1, NNLIGHT
         READ( IU_FILE,*,IOSTAT=IOS) (PROFILE(III,JJJ),JJJ=1,NLTYPE)
      ENDDO
         
      ! Close file
      CLOSE( IU_FILE )

      ! Return to calling program
      END SUBROUTINE INIT_LIGHTNING_NOX_NL

!------------------------------------------------------------------------------

      SUBROUTINE CLEANUP_LIGHTNING_NOX_NL
!
!******************************************************************************
!  Subroutine CLEANUP_LIGHTNING_NOX deallocates all module arrays. 
!  (bmy, 4/14/04, 1/31/07)
!
!  NOTES:
!  (1 ) Now deallocates OTDSCALE (ltm, bmy, 5/10/06)
!  (2 ) Rename OTDSCALE to OTD_REG_REDIST.  Now deallocate OTD_LOC_REDIST.
!        (bmy, 1/31/07)
!******************************************************************************
!
      !=================================================================
      ! CLEANUP_LIGHTNING_NOX begins here!
      !=================================================================
      IF ( ALLOCATED( PROFILE        ) ) DEALLOCATE( PROFILE        )
      IF ( ALLOCATED( SLBASE         ) ) DEALLOCATE( SLBASE         )
      IF ( ALLOCATED( OTD_REG_REDIST ) ) DEALLOCATE( OTD_REG_REDIST )
      IF ( ALLOCATED( OTD_LOC_REDIST ) ) DEALLOCATE( OTD_LOC_REDIST )

      ! Return to calling program
      END SUBROUTINE CLEANUP_LIGHTNING_NOX_NL

!------------------------------------------------------------------------------

      ! End of module
      END MODULE LIGHTNING_NOX_NL_MOD