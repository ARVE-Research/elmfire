! *****************************************************************************
MODULE ELMFIRE_SPREAD_RATE
! *****************************************************************************

USE ELMFIRE_VARS

IMPLICIT NONE

CONTAINS

! *****************************************************************************
RECURSIVE SUBROUTINE SURFACE_SPREAD_RATE(L,DUMMY_NODE)
! *****************************************************************************
! Applies Rothermel suface fire spread model to calculate surface fire rate
! of spread, heat per unit area, fireline intensity, flame length, and 
! reaction intensity

TYPE (DLL), INTENT(INOUT) :: L
TYPE (NODE), POINTER, INTENT(INOUT) :: DUMMY_NODE
!Local variables:
INTEGER :: I, ILH, NUM_NODES
REAL :: WS_LIMIT, WSMF_LIMITED, PHIS_MAX, MOMEX2, MOMEX3, MEX_LIVE, M_DEAD, M_LIVE,ETAM_DEAD, ETAM_LIVE, &
        RHOBEPSQIG_DEAD, RHOBEPSQIG_LIVE, RHOBEPSQIG, IR_DEAD, IR_LIVE, MOMEX, SUM_MPRIMENUMER
REAL, DIMENSION(1:6) :: M, QIG, FEPSQIG, FMC, FMEX, MPRIMENUMER
TYPE (FUEL_MODEL_TABLE_TYPE) :: FMT
TYPE(NODE), POINTER :: C
REAL, PARAMETER :: BTUPFT2MIN_TO_KWPM2 = 1.055/(60. * 0.3048 * 0.3048)

IF (ASSOCIATED (DUMMY_NODE) ) THEN
   NUM_NODES = 1
   C => DUMMY_NODE
ELSE
   NUM_NODES = L%NUM_NODES
   C => L%HEAD
ENDIF

DO I = 1, NUM_NODES

   IF (USE_BLDG_SPREAD_MODEL .AND. C%IFBFM .EQ. 91) THEN
      C => C%NEXT
      CYCLE
   ENDIF

   M(1)  = C%M1
   M(2)  = C%M10
   M(3)  = C%M100
   M(4)  = C%M1 !Set dynamic dead to m1
   M(5)  = C%MLH
   M(6)  = C%MLW

   ILH = MAX(MIN(NINT(100.*M(5)),120),30)
   FMT=FUEL_MODEL_TABLE_2D(C%IFBFM,ILH)

!Calculate live fuel moisture of extinction:
   MPRIMENUMER(1:4) = FMT%WPRIMENUMER(1:4) * M(1:4)
   SUM_MPRIMENUMER=SUM(MPRIMENUMER(1:4))
   MEX_LIVE = FMT%MEX_LIVE * (1. - FMT%R_MPRIMEDENOME14SUM_MEX_DEAD * SUM_MPRIMENUMER ) - 0.226

   MEX_LIVE = MAX(MEX_LIVE, FMT%MEX_DEAD)
   FMEX(5:6) = FMT%F(5:6) * MEX_LIVE

   FMEX(1:4) = FMT%FMEX(1:4)

   FMC(:) = FMT%F(:) * M(:)

   QIG(:) = 250. + 1116.*M(:)

   FEPSQIG(:) = FMT%FEPS(:) * QIG(:)

   RHOBEPSQIG_DEAD = FMT%RHOB * SUM(FEPSQIG(1:4))
   RHOBEPSQIG_LIVE = FMT%RHOB * SUM(FEPSQIG(5:6))
   RHOBEPSQIG = FMT%F_DEAD * RHOBEPSQIG_DEAD + FMT%F_LIVE * RHOBEPSQIG_LIVE

   M_DEAD    = SUM(FMC(1:4))
   MOMEX     = M_DEAD / FMT%MEX_DEAD
   MOMEX2    = MOMEX * MOMEX
   MOMEX3    = MOMEX2 * MOMEX
   ETAM_DEAD = 1.0 - 2.59*MOMEX + 5.11*MOMEX2 - 3.52*MOMEX3
   ETAM_DEAD = MAX(0.,MIN(ETAM_DEAD,1.))
   IR_DEAD   = FMT%GP_WND_EMD_ES_HOC * ETAM_DEAD

   M_LIVE    = SUM(FMC(5:6))
   MOMEX     = M_LIVE / MEX_LIVE
   MOMEX2    = MOMEX * MOMEX
   MOMEX3    = MOMEX2 * MOMEX
   ETAM_LIVE = 1.0 - 2.59*MOMEX + 5.11*MOMEX2 - 3.52*MOMEX3
   ETAM_LIVE = MAX(0.,MIN(ETAM_LIVE,1.))
   IR_LIVE   = FMT%GP_WNL_EML_ES_HOC * ETAM_LIVE

   C%IR = IR_DEAD + IR_LIVE !Btu/(ft^2-min)

!   WS_LIMIT = 96.8*C%IR**0.3333333 !Andrews, Cruz, and Rothermel (2013) limit
   WS_LIMIT = 0.9*C%IR !Original limit
   WSMF_LIMITED = MIN(C%WSMF, WS_LIMIT)

   C%PHIW_SURFACE = FMT%PHIWTERM * WSMF_LIMITED**FMT%B_COEFF

! Max slope factor is equal to max wind factor:
   PHIS_MAX = FMT%PHIWTERM * WS_LIMIT**FMT%B_COEFF
   C%PHIS_SURFACE = MIN(FMT%PHISTERM * C%TANSLP2, PHIS_MAX)

   C%VS0 = (C%ADJ + PERTURB_ADJ) * C%SUPPRESSION_ADJUSTMENT_FACTOR * DIURNAL_ADJUSTMENT_FACTOR * C%IR * FMT%XI / RHOBEPSQIG !ft/min
   C%VELOCITY_DMS_SURFACE = C%VS0 * (1.0 + C%PHIS_SURFACE + C%PHIW_SURFACE) !ft/min

! Convert reaction intensity to SI:
   C%IR           = C%IR * BTUPFT2MIN_TO_KWPM2 ! kW/m2
   C%HPUA_SURFACE = C%IR * FMT%TR * 60. ! kJ/m2
   C%FLIN_DMS_SURFACE = FMT%TR * C%IR * C%VELOCITY_DMS_SURFACE * 0.3048 ! kW/m

   C => C%NEXT
ENDDO

! *****************************************************************************
END SUBROUTINE SURFACE_SPREAD_RATE
! *****************************************************************************

! *****************************************************************************
RECURSIVE SUBROUTINE CROWN_SPREAD_RATE(L,DUMMY_NODE)
! *****************************************************************************

TYPE (DLL), INTENT(INOUT) :: L
TYPE (NODE), POINTER, INTENT(INOUT) :: DUMMY_NODE

INTEGER :: I, IX, IY, NUM_NODES
REAL :: WS10KMPH, CROSA, R0, CAC, FMCTERM, CBD_EFF, CBH_EFF, CROS, FLIN_SURFACE
TYPE(NODE), POINTER :: C
REAL, PARAMETER :: MPH_20FT_TO_KMPH_10M = 1.609 / 0.87 ! 1.609 km/h per mi/h; divide by 0.87 to go from 20 ft to 10 m
LOGICAL, PARAMETER :: USE_FLIN_DMS_SURFACE = .TRUE.

IF (ASSOCIATED (DUMMY_NODE) ) THEN
   NUM_NODES = 1
   C => DUMMY_NODE
ELSE
   NUM_NODES = L%NUM_NODES
   C => L%HEAD
ENDIF

DO I = 1, NUM_NODES
   IX=C%IX
   IY=C%IY

   IF (USE_FLIN_DMS_SURFACE) THEN
      FLIN_SURFACE=C%FLIN_DMS_SURFACE
   ELSE
      FLIN_SURFACE=C%FLIN_SURFACE
   ENDIF

   IF (C%VS0 .GT. 0. .AND. FLIN_SURFACE .GT. 0. .AND. CBD%R4(IX,IY,1) .GT. 1E-3 .AND. CC%R4(IX,IY,1) .GT. 1E-3) THEN 
      CROS = 0.

      IF (C%CRITICAL_FLIN .GT. 1E9) THEN
         C%HPUA_CANOPY = CBD%R4(IX,IY,1) * MAX(CH%R4(IX,IY,1) - CBH%R4(IX,IY,1),0.) * 12000. !kJ/m2
         IF (CBH%R4(IX,IY,1) .GE. 0.) THEN
            FMCTERM = 460. + 26. * C%FMC
            CBH_EFF = MAX(CBH%R4(IX,IY,1) + PERTURB_CBH, 0.1)
            C%CRITICAL_FLIN = (0.01 * CBH_EFF * FMCTERM) ** 1.5
         ELSE
            C%CRITICAL_FLIN = 9E9
         ENDIF
      ENDIF

      IF (FLIN_SURFACE .GT. C%CRITICAL_FLIN) THEN
         CBD_EFF  = MAX(CBD%R4(IX,IY,1) + PERTURB_CBD, 0.01)
         WS10KMPH = C%WS20_NOW * MPH_20FT_TO_KMPH_10M
         CROSA    = CROWN_FIRE_ADJ * 11.02 * WS10KMPH**0.9 * CBD_EFF**0.19 * EXP(-0.17*100.0*C%M1) / 0.3048 ! ft / min
         CROSA    = MIN(CROSA,CROWN_FIRE_SPREAD_RATE_LIMIT) ! ft/min
         R0       = (3.0 / CBD_EFF) / 0.3048 !ft/min
         CAC      = CROSA / R0

         IF (CAC .GT. 1) THEN !Active crown fire
            IF (CC%R4(IX,IY,1) .GE. CRITICAL_CANOPY_COVER) THEN 
               C%CROWN_FIRE = 2
               CROS = CROSA
               C%PHIW_CROWN = MIN(MAX(CROS / MAX(C%VS0, 0.001) - 1.0, 0.0), 200.0)
            ELSE
               C%CROWN_FIRE = 1
            ENDIF
         ELSE ! Passive crown fire
            C%CROWN_FIRE = 1
            IF (CC%R4(IX,IY,1) .GE. CRITICAL_CANOPY_COVER) THEN
               CROS = CROSA * EXP(-CAC)
               C%PHIW_CROWN = MIN(MAX(CROS / MAX(C%VS0,0.001) - 1.0, 0.0), 200.0)
            ENDIF
         ENDIF

      ENDIF ! FLIN_SURFACE .GT. C%CRITICAL_FLIN

   ENDIF ! CBD .GT. 1E-3 .AND. CC .GT. 1E-3
   C => C%NEXT
ENDDO ! I = 1, L%NUM_NODES

! *****************************************************************************
END SUBROUTINE CROWN_SPREAD_RATE
! *****************************************************************************

! *****************************************************************************
SUBROUTINE HAMADA(C)
! *****************************************************************************
! USE HAMADA MODEL TO CALCULATE THE ROS AT ANY WIND DIRECTION RELATIVE TO A GIVEN DIRECTION OF FIRE FRONT
! This subroutine is a contribution from Yiren Qin (yqin123@umd.edu)

TYPE(NODE), POINTER, INTENT(INOUT) :: C

REAL :: A_0 , D , F_B , V , X_T ! INPUTS 

! COEFFICIENT FOR HAMADA MODEL 
REAL, PARAMETER :: &
   C_14 = 1.6, C_24 = 0.1, C_34 = 0.007, C_44 = 25.0, C_54 = 2.5 , &
   C_1S = 1.0, C_2S = 0.0, C_3S = 0.005, C_4S = 5.0 , C_5S = 0.25, & 
   C_1U = 1.0, C_2U = 0.0, C_3U = 0.002, C_4U = 5.0 , C_5U = 0.2

REAL :: CV_4 , CV_S , CV_U 
REAL :: K_D , K_S , K_U, K_D_C , K_S_C , K_U_C , T_4 , T_S , T_U , & 
        V_D , V_D_C , V_S , V_S_C , V_U , V_U_C 

! HAMADA ELLIPSE DEFINITION 
X_T = 120.0      ! TIME IN MINUTES, the ROS predicted by Hamada model is a function of time, but will converge to a constant value in short. 
V   = C%WS20_NOW * 0.447 ! WIND SPEED , M / S 

! These values are taken at constant at this stage, but should vary with the footprint.
!A_0 = 23        ! AVERAGE BUILDING PLAN DIMENSION , M 
!D   = 45         ! AVERAGE BUILDING SEPERATION , M 
!F_B = 0       ! RATIO OF FIRE RESISTANCE BUILDINGS

A_0 = BLDG_AREA%R4 (C%IX,C%IY,1) ! AVERAGE BUILDING PLAN DIMENSION , M 
D   = BLDG_SEPARATION_DIST%R4 (C%IX,C%IY,1) ! AVERAGE BUILDING SEPERATION , M 
F_B = BLDG_NONBURNABLE_FRAC%R4(C%IX,C%IY,1) ! RATIO OF FIRE RESISTANCE BUILDINGS

CV_4 = C_14 * ( 1 + C_24 * V + C_34 * V ** 2 ) 
CV_S = C_1S * ( 1 + C_2S * V + C_3S * V ** 2 ) 
CV_U = C_1U * ( 1 + C_2U * V + C_3U * V ** 2 ) 

! TIME IN MINUTES THE FULLY DEVELOPED FIRE REQUIRES TO ADVANCE TO THE NEXT BUILDING 
T_4 = (( 1-F_B ) * ( 3 + 0.375 * A_0 + ( 8 * D / ( C_44 + C_54 * V ) ) ) + & 
      F_B * ( 5 + 0.625 * A_0 + 16 * D / ( C_44 + C_54 * V ) ) )/ CV_4 
T_S = (( 1-F_B ) * ( 3 + 0.375 * A_0 + ( 8 * D / ( C_4S + C_5S * V ) ) ) + & 
      F_B * ( 5 + 0.625 * A_0 + 16 * D / ( C_4S + C_5S * V ) )) / CV_S 
T_U = (( 1-F_B ) * ( 3 + 0.375 * A_0 + ( 8 * D / ( C_4U + C_5U * V ) ) ) + & 
      F_B * ( 5 + 0.625 * A_0 + 16 * D / ( C_4U + C_5U * V ) ) )/ CV_U 

K_D = MAX(( A_0 + D ) / T_4 * X_T ,1E-10)
K_S = MAX(( A_0 / 2 + D ) + ( A_0 + D ) / T_S * ( X_T-T_S ),1E-10) 
K_U = MAX(( A_0 / 2 + D ) + ( A_0 + D ) / T_U * ( X_T-T_U ),1E-10)

V_D = MAX(( A_0 + D ) / T_4,1E-10) 
V_S = MAX(( A_0 + D ) / T_S,1E-10) 
V_U = MAX(( A_0 + D ) / T_U,1E-10)

! HAZUS CORRECTION
IF(V .LE. 10) THEN

   K_D_C = K_D * V/10.0+SQRT((K_D+K_U)/2*K_S)*(1-V/10.0)
   K_U_C = K_U * V/10.0+SQRT((K_D+K_U)/2*K_S)*(1-V/10.0)
   K_S_C = K_S * V/10.0+SQRT((K_D+K_U)/2*K_S)*(1-V/10.0)
   
   V_D_C = MAX(V_D * V / 10 + & 
            ( K_D * V_S + V_D * K_S + K_U * V_S + V_U * K_S ) * & 
           SQRT( 2 / ( K_D + K_U )/K_S ) * ( 1-V / 10 )/4,1E-10)
   V_S_C = MAX(V_S * V / 10 + & 
            ( K_D * V_S + V_D * K_S + K_U * V_S + V_U * K_S ) * & 
           SQRT( 2 / ( K_D + K_U )/K_S ) * ( 1-V / 10 )/4,1E-10)
   V_U_C = MAX(V_U * V / 10 + & 
            ( K_D * V_S + V_D * K_S + K_U * V_S + V_U * K_S ) * & 
           SQRT( 2 / ( K_D + K_U )/K_S ) * ( 1-V / 10 )/4 ,1E-10)

   V_D = V_D_C !M/MIN
   V_S = V_S_C !M/MIN
   V_U = V_U_C !M/MIN
ENDIF

IF(MIN(K_D,MIN(K_S,K_U)) .LE. 1E-1) THEN
    V_D = K_D/MAX(X_T,1E-10)
    V_S = K_S/MAX(X_T,1E-10)
    V_U = K_U/MAX(X_T,1E-10)
ENDIF

C%VELOCITY_DMS = V_D /0.3048 ! Unit Transform to ft/min
C%VBACK = V_U/0.3048
C%LOW = MIN((V_D+V_U)/2/V_S,10.0)

! *****************************************************************************
END SUBROUTINE HAMADA
! *****************************************************************************

! *****************************************************************************
SUBROUTINE UMD_UCB_BLDG_SPREAD(C, LB, T)
! *****************************************************************************

USE ELMFIRE_VARS

TYPE(NODE), POINTER, INTENT(INOUT) :: C
TYPE(DLL) , INTENT(IN) :: LB
TYPE(NODE), POINTER :: LB_P
INTEGER :: I, TEMP_SX, TEMP_SY, DEL_X, DEL_Y, IX_LOW_BORDER, IY_LOW_BORDER, IX_HIGH_BORDER, IY_HIGH_BORDER, &
           IX_TEMP, IY_TEMP, HAZ
REAL, INTENT(IN) :: T
REAL :: TARGET_R, TARGET_R_METERS, TARGET_THETA, WIND_THETA, TARGET_THETA_F, MAX_ELLIPSE_DIST, ELLIPSE_DIST_THETA, &
        DFC_CHECKER, DFC_FACTOR, DFC_HEAT_RECEIVED, RAD_LIMIT_THETA, RAD_CHECKER, DELTA_RAD, RAD_FACTOR, &
        RAD_EFF_DIST, RAD_HEAT_RECEIVED, V_S, SUM_ELLIPSE, FLAME_FRONT, FLAME_SIDE, FLAME_BACK, UCB_DIV, &
        DFC_COEFF, RAD_COEFF, FTP_PA, LHRR_PEAK,ANALYSIS_CELLSIZE_SQUARED,RANALYSIS_CELLSIZE, HALF_ANALYSIS_CELLSIZE, &
        RDEL_X, RDEL_Y, ELLIPSE_MINOR_SQUARED, TOTAL_DFC, TOTAL_RADIATION, RAD_PER_SQCELL, &
        DFC_HEAT_FLUX, RAD_HEAT_FLUX, DFC_SIGMOID, RAD_SIGMOID

DFC_COEFF = 1 - BUILDING_FUEL_MODEL_TABLE(C%IBLDGFM)%NONBURNABLE_FRAC
RAD_COEFF = BUILDING_FUEL_MODEL_TABLE(C%IBLDGFM)%ABSORPTIVITY
! FTP_PA = BUILDING_FUEL_MODEL_TABLE(C%IBLDGFM)%FTP_CRIT

! Set a few constants:
ANALYSIS_CELLSIZE_SQUARED = ANALYSIS_CELLSIZE * ANALYSIS_CELLSIZE
RANALYSIS_CELLSIZE = 1. / ANALYSIS_CELLSIZE !Reciprocal analysis cellsize
HALF_ANALYSIS_CELLSIZE = 0.5 * ANALYSIS_CELLSIZE

LB_P => LB%HEAD

HAZ = 5

TEMP_SX = 0
TEMP_SY = 0

TOTAL_DFC = 0.0
TOTAL_RADIATION = 0.0

IX_TEMP = C%IX - HAZ
IY_TEMP = C%IY - HAZ

IX_LOW_BORDER = MAX(1, IX_TEMP)
IY_LOW_BORDER = MAX(1, IY_TEMP)

IX_TEMP = C%IX + HAZ
IY_TEMP = C%IY + HAZ

IX_HIGH_BORDER = MIN(ANALYSIS_NCOLS, IX_TEMP)
IY_HIGH_BORDER = MIN(ANALYSIS_NROWS, IY_TEMP)

DO I = 1, LB%NUM_NODES

   IF ((LB_P%IX .GE. IX_LOW_BORDER) .AND. (LB_P%IY .GE. IY_LOW_BORDER) .AND. (LB_P%IX .LE. IX_HIGH_BORDER) .AND. (LB_P%IY .LE. IY_HIGH_BORDER)) THEN
      
!   IF ((LB_P%IX .LT. IX_LOW_BORDER) .OR. (LB_P%IY .LT. IY_LOW_BORDER) .OR. (LB_P%IX .GT. IX_HIGH_BORDER) .OR. (LB_P%IY .GT. IY_HIGH_BORDER)) THEN
!      CYCLE
!   ENDIF 

   
      LHRR_PEAK = BUILDING_FUEL_MODEL_TABLE(LB_P%IBLDGFM)%HRRPUA_PEAK
      ELLIPSE_MINOR_SQUARED = LB_P%ELLIPSE_PARAMETERS%ELLIPSE_MINOR * LB_P%ELLIPSE_PARAMETERS%ELLIPSE_MINOR 

      DEL_X = C%IX - LB_P%IX
      IF (DEL_X .LT. 0) THEN
         TEMP_SX = TEMP_SX - 1
      ELSE
        TEMP_SX = TEMP_SX + 1
      ENDIF

      DEL_Y = C%IY - LB_P%IY
      IF (DEL_Y .LT. 0) THEN
         TEMP_SY = TEMP_SY - 1
      ELSE
         TEMP_SY = TEMP_SY + 1
      ENDIF

      RDEL_X = REAL(DEL_X)
      RDEL_Y = REAL(DEL_Y)

      TARGET_R = SQRT( RDEL_X*RDEL_X + RDEL_Y*RDEL_Y)
      TARGET_R_METERS = TARGET_R*ANALYSIS_CELLSIZE

      IF (TARGET_R .EQ. 0) THEN
         CYCLE
      ENDIF
      
      TARGET_THETA = ATAN2(RDEL_Y, RDEL_X) !in radians
      WIND_THETA = PIO180 * (270. - LB_P%WD20_NOW) !in radians
      TARGET_THETA_F = TARGET_THETA - WIND_THETA !in radians

   ! Why is ANALYSIS_CELLSIZE raised to the 0 power here? 
      MAX_ELLIPSE_DIST = 0.3 * LB_P%ELLIPSE_PARAMETERS%DIST_DOWNWIND * (LB_P%ELLIPSE_PARAMETERS%ELLIPSE_MAJOR - LB_P%ELLIPSE_PARAMETERS%ELLIPSE_ECCENTRICITY) / ELLIPSE_MINOR_SQUARED

   !   IF (LB_P%IFBFM .NE. 91) LHRR_PEAK = RANALYSIS_CELLSIZE * LB_P%FLIN_SURFACE

      CALL HRR_TRANSIENT(LB_P, T)

   ! Direct Flame Contact
      ELLIPSE_DIST_THETA = MAX_ELLIPSE_DIST*ELLIPSE_MINOR_SQUARED / (LB_P%ELLIPSE_PARAMETERS%ELLIPSE_MAJOR - LB_P%ELLIPSE_PARAMETERS%ELLIPSE_ECCENTRICITY*COS(TARGET_THETA_F))

      DFC_CHECKER = RANALYSIS_CELLSIZE * (ELLIPSE_DIST_THETA + HALF_ANALYSIS_CELLSIZE - TARGET_R_METERS)

      DFC_FACTOR = AMAX1(0.0,AMIN1(1.0,DFC_CHECKER))

      DFC_HEAT_RECEIVED = DFC_COEFF*DFC_FACTOR*LB_P%HRR_TRANSIENT

   ! Radiation
      RAD_LIMIT_THETA = ELLIPSE_DIST_THETA + LB_P%RAD_DIST
      RAD_CHECKER = RANALYSIS_CELLSIZE * (RAD_LIMIT_THETA + HALF_ANALYSIS_CELLSIZE - TARGET_R_METERS)

      DELTA_RAD = AMAX1(0.0,AMIN1(1.0,RAD_CHECKER))
      RAD_FACTOR = DELTA_RAD - DELTA_RAD*DFC_FACTOR

      IF ((DFC_FACTOR .LT. 1) .AND. (DFC_FACTOR .GT. 0)) THEN
           RAD_EFF_DIST = ANALYSIS_CELLSIZE - DFC_FACTOR*ANALYSIS_CELLSIZE
      ELSE
           RAD_EFF_DIST  = TARGET_R_METERS - ELLIPSE_DIST_THETA
      ENDIF

      RAD_HEAT_RECEIVED = (0.3*DFC_COEFF*RAD_COEFF*RAD_FACTOR*LB_P%HRR_TRANSIENT*ANALYSIS_CELLSIZE_SQUARED)/(4*PI*RAD_EFF_DIST*RAD_EFF_DIST)
 
      C%HEAT_VALUE = C%HEAT_VALUE + (DFC_HEAT_RECEIVED + RAD_HEAT_RECEIVED)*SIMULATION_DT*ANALYSIS_CELLSIZE_SQUARED

      TOTAL_DFC = TOTAL_DFC + DFC_HEAT_RECEIVED*SIMULATION_DT*ANALYSIS_CELLSIZE_SQUARED
      TOTAL_RADIATION = TOTAL_RADIATION + RAD_HEAT_RECEIVED*SIMULATION_DT*ANALYSIS_CELLSIZE_SQUARED
   
!   ELSE
!      CYCLE      
   ENDIF
   
   LB_P => LB_P%NEXT
ENDDO

DFC_HEAT_FLUX = TOTAL_DFC/ANALYSIS_CELLSIZE_SQUARED
RAD_HEAT_FLUX = TOTAL_RADIATION/ANALYSIS_CELLSIZE_SQUARED

DFC_SIGMOID = 500/(1 + EXP(2.5 - 0.01*DFC_HEAT_FLUX))
RAD_SIGMOID = 100/(1 + EXP(2.5 - 0.05*DFC_HEAT_FLUX))




IF (TOTAL_DFC .GT. 400000) TOTAL_DFC = DFC_SIGMOID * ANALYSIS_CELLSIZE_SQUARED
IF (TOTAL_RADIATION .GT. 90000) TOTAL_RADIATION = RAD_SIGMOID * ANALYSIS_CELLSIZE_SQUARED

C%TOTAL_DFC_RECEIVED = TOTAL_DFC
C%TOTAL_RAD_RECEIVED = TOTAL_RADIATION

RAD_PER_SQCELL = (TOTAL_DFC + TOTAL_RADIATION)/ANALYSIS_CELLSIZE_SQUARED

IF ((TOTAL_DFC + TOTAL_RADIATION)>30000) THEN 
   FTP_PA = 3000
ELSE
   FTP_PA = 3000000/(RAD_PER_SQCELL*RAD_PER_SQCELL)
ENDIF

   
   

IF (C%WS20_NOW .LE. 35) THEN
   UCB_DIV = 1.8
ELSE
   UCB_DIV = 1.0
ENDIF

!C%ABSOLUTE_U = 60*C%HEAT_VALUE/(0.3048*SIMULATION_DT*ANALYSIS_CELLSIZE*FTP_PA)/UCB_DIV

C%ABSOLUTE_U = 60*(TOTAL_DFC + TOTAL_RADIATION)/(0.3048*SIMULATION_DT*ANALYSIS_CELLSIZE*FTP_PA)/UCB_DIV


IF (TEMP_SX .LT. 0) THEN
   C%SIGN_X = -1
ELSE
   C%SIGN_X = 1
ENDIF

IF (TEMP_SY .LT. 0) THEN
   C%SIGN_Y = -1
ELSE
   C%SIGN_Y = 1
ENDIF

CALL ELLIPSE_UCB(C)

SUM_ELLIPSE = PI*C%ELLIPSE_PARAMETERS%ELLIPSE_MAJOR*C%ELLIPSE_PARAMETERS%ELLIPSE_MINOR

FLAME_FRONT = C%ELLIPSE_PARAMETERS%ELLIPSE_MAJOR + C%ELLIPSE_PARAMETERS%ELLIPSE_ECCENTRICITY
FLAME_SIDE = 2*C%ELLIPSE_PARAMETERS%ELLIPSE_MINOR
FLAME_BACK = C%ELLIPSE_PARAMETERS%ELLIPSE_MAJOR - C%ELLIPSE_PARAMETERS%ELLIPSE_ECCENTRICITY

!SUM_ELLIPSE = FLAME_FRONT + FLAME_SIDE + FLAME_BACK

C%VELOCITY_DMS = C%ABSOLUTE_U*FLAME_FRONT*ANALYSIS_CELLSIZE/(SUM_ELLIPSE) ! Unit Transform to ft/min
C%VBACK = C%ABSOLUTE_U*FLAME_BACK*ANALYSIS_CELLSIZE/(SUM_ELLIPSE)
V_S = C%ABSOLUTE_U*FLAME_SIDE*ANALYSIS_CELLSIZE/(SUM_ELLIPSE)

IF (V_S .GT. 1E-4) THEN
   C%LOW = AMIN1((C%VELOCITY_DMS+C%VBACK)/2/V_S,10.0)
ELSE
   C%LOW = 1.0
ENDIF

C%HEAT_VALUE = 0.

! *****************************************************************************
END SUBROUTINE UMD_UCB_BLDG_SPREAD
! ****************************************************************************

! *****************************************************************************
SUBROUTINE ELLIPSE_UCB(C)
! *****************************************************************************

USE ELMFIRE_VARS

TYPE(NODE), POINTER, INTENT(INOUT) :: C
REAL :: V_MPS, EB2, D1, D2, D3, S1, S2, S3, U1, U2, U3, HAMADA_A, HAMADA_D

V_MPS = C%WS20_NOW * 0.447 ! WIND SPEED , M / S

IF (C%IFBFM .EQ. 91) THEN
   C%ELLIPSE_PARAMETERS%FOREST_FACTOR = 1
ELSE
   C%ELLIPSE_PARAMETERS%FOREST_FACTOR = 3
ENDIF

HAMADA_A = BLDG_AREA%R4 (C%IX,C%IY,1) ! AVERAGE BUILDING PLAN DIMENSION , M 
HAMADA_D = BLDG_SEPARATION_DIST%R4 (C%IX,C%IY,1) ! AVERAGE BUILDING SEPERATION , M 

! This is regression from HAMADA. Subject of changes. ------------------------------------------

IF (V_MPS .LT. 10) THEN  ! HAZUS CORRECTION

   D1 = 1.679463256 - 0.123901243*HAMADA_A + 0.307612446*HAMADA_D
   D2 = 78.62957398 + 1.536189561*HAMADA_A - 0.5662073*HAMADA_D

   S1 = -2.922896622 - 0.05550541*HAMADA_A + 0.017291361*HAMADA_D
   S2 = 39.31478699 + 0.768094781*HAMADA_A - 0.28310365*HAMADA_D

   U1 = -6.297892493 - 0.119654483*HAMADA_A + 0.037754535*HAMADA_D
   U2 = 78.62957398 + 1.536189561*HAMADA_A - 0.5662073*HAMADA_D

   C%ELLIPSE_PARAMETERS%DIST_DOWNWIND = C%WIND_PROP*(D1*V_MPS + D2)
   C%ELLIPSE_PARAMETERS%DIST_UPWIND = C%WIND_PROP*(U1*V_MPS + U2)
   C%ELLIPSE_PARAMETERS%DIST_SIDEWIND = C%WIND_PROP*(S1*V_MPS + S2)

ELSEIF (V_MPS .GT. 17.3) THEN  ! HIGH WIND SPEED

   D1 = -7.159031537 - 0.043555289*HAMADA_A - 0.14894238*HAMADA_D
   D2 = 394.4930697 + 0.720929023*HAMADA_A + 11.42149084*HAMADA_D

   S1 = -0.577270631 - 0.015285438*HAMADA_A + 0.012786629*HAMADA_D
   S2 = 38.11784939 + 0.800599307*HAMADA_A - 0.412476476*HAMADA_D

   U1 = -1.092711783 - 0.025390239*HAMADA_A + 0.016740663*HAMADA_D
   U2 = 52.39584604 + 1.104793131*HAMADA_A - 0.57241037*HAMADA_D

   C%ELLIPSE_PARAMETERS%DIST_DOWNWIND = C%WIND_PROP*(D1*V_MPS + D2)
   C%ELLIPSE_PARAMETERS%DIST_UPWIND = C%WIND_PROP*(U1*V_MPS + U2)
   C%ELLIPSE_PARAMETERS%DIST_SIDEWIND = C%WIND_PROP*(S1*V_MPS + S2)

ELSE  
   
   D1 = 4.099488028 - 0.000767118*HAMADA_A + 0.134372426*HAMADA_D
   D2 = -94.26651508 - 0.000694022*HAMADA_A - 3.053034015*HAMADA_D
   D3 = 615.192675 + 0.300438559*HAMADA_A + 19.34120221*HAMADA_D

   S1 = 0.437844987 + 0.008280661*HAMADA_A - 0.002833081*HAMADA_D
   S2 = -10.13978982 - 0.192922421*HAMADA_A + 0.067862023*HAMADA_D
   S3 = 66.32382799 + 1.282260348*HAMADA_A - 0.484673257*HAMADA_D

   U1 = 0.525004045 + 0.01046073*HAMADA_A - 0.004473105*HAMADA_D
   U2 = -12.4091466 - 0.249326233*HAMADA_A + 0.109759448*HAMADA_D
   U3 = 84.64808209 + 1.727651884*HAMADA_A - 0.801945211*HAMADA_D


   C%ELLIPSE_PARAMETERS%DIST_DOWNWIND = C%WIND_PROP*(D1*V_MPS**2 + D2*V_MPS + D3)
   C%ELLIPSE_PARAMETERS%DIST_UPWIND = C%WIND_PROP*(U1*V_MPS**2 + U2*V_MPS + U3)
   C%ELLIPSE_PARAMETERS%DIST_SIDEWIND = C%WIND_PROP*(S1*V_MPS**2 + S2*V_MPS + S3)

ENDIF

! ----------------------------------------------------------------------------------------

C%ELLIPSE_PARAMETERS%ELLIPSE_MAJOR = (C%ELLIPSE_PARAMETERS%DIST_DOWNWIND + C%ELLIPSE_PARAMETERS%DIST_UPWIND)/2
C%ELLIPSE_PARAMETERS%ELLIPSE_ECCENTRICITY = AMIN1(C%ELLIPSE_PARAMETERS%ELLIPSE_MAJOR/2,C%ELLIPSE_PARAMETERS%ELLIPSE_MAJOR - C%ELLIPSE_PARAMETERS%DIST_UPWIND)
EB2 = 1.0-(C%ELLIPSE_PARAMETERS%ELLIPSE_ECCENTRICITY/C%ELLIPSE_PARAMETERS%ELLIPSE_MAJOR)**2
C%ELLIPSE_PARAMETERS%ELLIPSE_MINOR = C%ELLIPSE_PARAMETERS%DIST_SIDEWIND/SQRT(EB2)

! *****************************************************************************
END SUBROUTINE ELLIPSE_UCB
! *****************************************************************************

! *****************************************************************************
SUBROUTINE HRR_TRANSIENT(BURNING_NODES, T)
! *****************************************************************************

USE ELMFIRE_VARS

TYPE(NODE), POINTER, INTENT(INOUT) :: BURNING_NODES
REAL ::  BURNING_TIME, EARLY_TIME, HRR_PEAK, DEVELOPED_TIME, DECAY_TIME
REAL, INTENT(IN) :: T

EARLY_TIME = BUILDING_FUEL_MODEL_TABLE(BURNING_NODES%IBLDGFM)%T_EARLY
DEVELOPED_TIME = BUILDING_FUEL_MODEL_TABLE(BURNING_NODES%IBLDGFM)%T_FULLDEV
DECAY_TIME = BUILDING_FUEL_MODEL_TABLE(BURNING_NODES%IBLDGFM)%T_DECAY
HRR_PEAK = BUILDING_FUEL_MODEL_TABLE(BURNING_NODES%IBLDGFM)%HRRPUA_PEAK

IF (BURNING_NODES%IFBFM .NE. 91) HRR_PEAK = BURNING_NODES%FLIN_SURFACE / ANALYSIS_CELLSIZE

BURNING_TIME = T - BURNING_NODES%TIME_OF_ARRIVAL

IF (BURNING_TIME .LE. EARLY_TIME) THEN
   BURNING_NODES%HRR_TRANSIENT = (HRR_PEAK/ EARLY_TIME)*BURNING_TIME
ELSEIF ((BURNING_TIME .GT. EARLY_TIME) .AND. (BURNING_TIME .LE. DEVELOPED_TIME)) THEN
   BURNING_NODES%HRR_TRANSIENT = HRR_PEAK
ELSEIF (BURNING_TIME .GT. DECAY_TIME) THEN
   BURNING_NODES%HRR_TRANSIENT = 0.
ELSE
   BURNING_NODES%HRR_TRANSIENT = (HRR_PEAK/(DEVELOPED_TIME - DECAY_TIME))*(BURNING_TIME - DECAY_TIME)
ENDIF

BURNING_NODES%HRR_TRANSIENT = AMAX1(0.0, BURNING_NODES%HRR_TRANSIENT)

! *****************************************************************************
END SUBROUTINE HRR_TRANSIENT
! *****************************************************************************

END MODULE
