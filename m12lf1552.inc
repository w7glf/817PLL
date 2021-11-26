
;----- CONFIG1 Options --------------------------------------------------
_eFOSC_INTOSC     EQU  H'3FFC'    ; INTOSC oscillator: I/O function on CLKIN pin
_eFOSC_ECL        EQU  H'3FFD'    ; ECL, External Clock, Low Power Mode (0-0.5 MHz): device clock supplied to CLKIN pin
_eFOSC_ECM        EQU  H'3FFE'    ; ECM, External Clock, Medium Power Mode (0.5-4 MHz): device clock supplied to CLKIN pin
_eFOSC_ECH        EQU  H'3FFF'    ; ECH, External Clock, High Power Mode (4-20 MHz): device clock supplied to CLKIN pin

_eWDTE_OFF        EQU  H'3FE7'    ; WDT disabled
_eWDTE_SWDTEN     EQU  H'3FEF'    ; WDT controlled by the SWDTEN bit in the WDTCON register
_eWDTE_NSLEEP     EQU  H'3FF7'    ; WDT enabled while running and disabled in Sleep
_eWDTE_ON         EQU  H'3FFF'    ; WDT enabled

_ePWRTE_ON        EQU  H'3FDF'    ; PWRT enabled
_ePWRTE_OFF       EQU  H'3FFF'    ; PWRT disabled

_eMCLRE_OFF       EQU  H'3FBF'    ; MCLR/VPP pin function is digital input
_eMCLRE_ON        EQU  H'3FFF'    ; MCLR/VPP pin function is MCLR

_eCP_ON           EQU  H'3F7F'    ; Program memory code protection is enabled
_eCP_OFF          EQU  H'3FFF'    ; Program memory code protection is disabled

_eBOREN_OFF       EQU  H'39FF'    ; Brown-out Reset disabled
_eBOREN_SBODEN    EQU  H'3BFF'    ; Brown-out Reset controlled by the SBOREN bit in the BORCON register
_eBOREN_NSLEEP    EQU  H'3DFF'    ; Brown-out Reset enabled while running and disabled in Sleep
_eBOREN_ON        EQU  H'3FFF'    ; Brown-out Reset enabled

_eCLKOUTEN_ON     EQU  H'37FF'    ; CLKOUT function is enabled on the CLKOUT pin
_eCLKOUTEN_OFF    EQU  H'3FFF'    ; CLKOUT function is disabled. I/O or oscillator function on the CLKOUT pin

;----- CONFIG2 Options --------------------------------------------------
_eWRT_ALL         EQU  H'3FFC'    ; 000h to FFFh write protected, no addresses may be modified by PMCON control
_eWRT_HALF        EQU  H'3FFD'    ; 000h to 7FFh write protected, 800h to FFFh may be modified by PMCON control
_eWRT_BOOT        EQU  H'3FFE'    ; 000h to 1FFh write protected, 200h to FFFh may be modified by PMCON control
_eWRT_OFF         EQU  H'3FFF'    ; Write protection off

_eSTVREN_OFF      EQU  H'3DFF'    ; Stack Overflow or Underflow will not cause a Reset
_eSTVREN_ON       EQU  H'3FFF'    ; Stack Overflow or Underflow will cause a Reset

_eBORV_HI         EQU  H'3BFF'    ; Brown-out Reset Voltage (Vbor), high trip point selected.
_eBORV_LO         EQU  H'3FFF'    ; Brown-out Reset Voltage (Vbor), low trip point selected.
_eBORV_19         EQU  H'3FFF'    ; Brown-out Reset Voltage (Vbor), low trip point selected.

_eLPBOR_ON        EQU  H'37FF'    ; Low-Power BOR is enabled
_eLPBOR_OFF       EQU  H'3FFF'    ; Low-Power BOR is disabled

_eLVP_OFF         EQU  H'DFFF'    ; High-voltage on MCLR/VPP must be used for programming
_eLVP_ON          EQU  H'3FFF'    ; Low-voltage programming enabled

