;*********************************************************************
; *
;*************************************************************************
; Title	:    I2C (Single) Master Implementation
; Author:    Peter Fleury <pfleury@gmx.ch>  http://jump.to/fleury
;            based on Atmel Appl. Note AVR300
;            Changes by Ray Cannon W7GLF for 817 PLL
;
; File:      $Id: i2cmaster.S,v 1.12 2008/03/02 08:51:27 peter Exp $
; Software:  AVR-GCC 3.3 or higher
; Target:    any AVR device
;
; DESCRIPTION
; 	Basic routines for communicating with I2C slave devices. This
;	"single" master implementation is limited to one bus master on the
;	I2C bus. 
;  
;       Based on the Atmel Application Note AVR300, corrected and adapted 
;       to GNU assembler and AVR-GCC C call interface
;       Replaced the incorrect quarter period delays found in AVR300 with 
;       half period delays. 
;
; USAGE
; 	Adapt the SCL and SDA port and pin definitions and eventually 
;	the delay routine to your target !
; 	Use 4.7k pull-up resistor on the SDA and SCL pin.
;
; NOTES
;	The I2C routines can be called either from non-interrupt or
;	interrupt routines, not both.
;
;*************************************************************************
; *
; Filename: init.asm *
; Date: 07/18/2000 *
; Revision: 1.00 *
; *
;*********************************************************************
; *
; Files required: *
; *
; init.asm *	
; *
; p12lf1552.inc *
; m12lf1552.inc *
; *
; *
;*********************************************************************
; *
; Notes: *
; *
; *
;********************************************************************/
; #include <p12lf1552.inc> ; processor specific variable definitions
	list p=12lf1552 ; list directive to define processor
#include <p12lf1552.inc> ; processor specific variable definitions
#include "m12lf1552.inc" ; processor specific variable definitions
	__CONFIG _CONFIG1, _eFOSC_INTOSC & _eWDTE_OFF & _ePWRTE_OFF & _eMCLRE_ON & _eCP_OFF & _eBOREN_OFF & _eCLKOUTEN_OFF
	__CONFIG _CONFIG2, _eLVP_OFF & _eLPBOR_OFF & _eBORV_LO & _eSTVREN_OFF & _eWRT_OFF
	errorlevel -302 ; suppress bank warning

		RADIX dec

; ****************************************************************
; I2C routines developed by Davide Bucci, version 1.0, August 2004
; ****************************************************************

DEBUG		equ		0
ARDUINO_VAL	equ		1  ; Use register values reverse engineered from Arduino; else values from SiLAB ClockBuilder
RESET_PLL	equ		0	; I don't think we need to do this.

; Control lines of the I2C interface
LED		equ		2
NORFDET	equ		2	; NORFDET is LOW when RF Detected
SCL     equ     4
SDA     equ     5
I2CPORT equ     PORTA
I2CTRIS equ     TRISA

I2C_WRITE equ	b'11000000'		; I2C address for writing to the Si5351A (0x60 shifted left)
I2C_READ  equ	b'11000001'		; I2C address for reading to the Si5351A

; SI5351 definitons
SI_CLK0_CONTROL	equ	16		; Register definitions
SI_CLK1_CONTROL	equ	17
SI_CLK2_CONTROL	equ	18
SI_SYNTH_PLL_A	equ	26
SI_SYNTH_PLL_B	equ	34
SI_SYNTH_MS_0	equ	42
SI_SYNTH_MS_1	equ	50
SI_SYNTH_MS_2	equ	58
SI_PLL_RESET	equ	177

SI_R_DIV_1		equ	b'00000000'			; R-division ratio definitions
SI_R_DIV_2		equ	b'00010000'
SI_R_DIV_4		equ	b'00100000'
SI_R_DIV_8		equ	b'00110000'
SI_R_DIV_16		equ	b'01000000'
SI_R_DIV_32		equ	b'01010000'
SI_R_DIV_64		equ b'01100000'
SI_R_DIV_128	equ	b'01110000'

SI_CLK_SRC_PLL_A	equ	b'00000000'
SI_CLK_SRC_PLL_B	equ	b'00100000'

;  Macros


LED_ON		MACRO				; For debugging
#if			DEBUG
			banksel	PORTA 	; select SFR bank
			bsf		PORTA, LED
#endif
			ENDM

LED_OFF		MACRO				; For debugging
#if			DEBUG
			banksel	PORTA 	; select SFR bank
			bcf		PORTA, LED
#endif
			ENDM

WRITE_REG	MACRO	addr,value
			local	retry_write
retry_write:
			BANKSEL	PORTA
			movlw	addr
			movwf	i2caddr
			movlw	value
			movwf	i2cdata
			call	i2cSendRegister
			iorlw	0
			btfss	STATUS, Z
			goto 	retry_write	; Not zero
			ENDM

SETLOW		MACRO	register
			call	i2c_delay_T2
			banksel	I2CTRIS
			bcf		I2CTRIS,register 
	        banksel I2CPORT
			bcf		I2CPORT,register
			call	i2c_delay_T2
			ENDM

SETHIGH		MACRO	register
			call	i2c_delay_T2
			banksel	I2CTRIS
			bsf		I2CTRIS,register	; Tristate will force high 
	        banksel I2CPORT
			call	i2c_delay_T2
			ENDM

; Variables, substitute adresses of free RAM bytes

		cblock  0x20

		w_temp					; variable used for context saving
		status_temp				; variable used for context saving
		pclath_temp				; variable used for context saving
		tmp
		tmpwr
		com
		slow_timer1
		slow_timer2
		sav_w
		sav_status
		sav_w2
		sav_status2
		sav_w_hex
		sav_status_hex

; High level parameters for i2cSendRegister and i2cReadRegister

		i2caddr
		i2cdata
		endc


MAIN_CODE
;----------------------------------------------------------------------
; ********************* RESET VECTOR LOCATION ********************
;----------------------------------------------------------------------
    
		ORG  0x000 ; processor reset vector
		goto start ; go to beginning of program

;----------------------------------------------------------------------
; ******************* INTERRUPT VECTOR LOCATION *******************
;----------------------------------------------------------------------
		ORG 0x4 ; interrupt vector location
		movwf w_temp ; save off current W register contents
		movf STATUS,w ; move status register into W register
		clrf STATUS ; ensure file register bank set to 0
		movwf status_temp ; save off contents of STATUS register
		movf PCLATH,w
		movwf pclath_temp ; save off current copy of PCLATH
		clrf PCLATH ; reset PCLATH to page 0

		; Just wake up from sleep
		nop

		; Clear interrupt flag
		banksel	IOCAF
		movlw	0xff
		xorwf	IOCAF, W
		andwf	IOCAF, F
		BCF		INTCON, IOCIF	; clear IOCIF bit

		
exit_isr
		clrf STATUS ; ensure file register bank set to 0
		movf pclath_temp,w
		movwf PCLATH ; restore PCLATH
		movf status_temp,w ; retrieve copy of STATUS register
		movwf STATUS ; restore pre-isr STATUS register contents
		swapf w_temp,f ;
		swapf w_temp,w ; restore pre-isr W register contents
		retfie ; return from interrupt

;----------------------------------------------------------------------
; ******************* MAIN CODE START LOCATION ******************
;----------------------------------------------------------------------
start
	; ******************* INITIALIZE PORTS *************************
		banksel	PORTA 	; select SFR bank
		clrf	PORTA 	; initialize PORTS
		banksel	LATA 	; select SFR bank
		clrf	LATA 	; initialize PORTS
		banksel	ANSELA 	; select SFR bank
		clrf	ANSELA	; initialize PORTS
		banksel	SSPCON1
		clrf	SSPCON1
		banksel	FSR0H 	; select SFR bank
		movlw	b'00000000' 
		movwf	FSR0H
		banksel	TRISA
		movlw	b'00111111'		; Set all input 
		movwf	TRISA
#if	DEBUG
		bcf		TRISA, LED		; LED		// Output
#else
		bsf		TRISA, NORFDET	; 10 MHz Detect - Input
#endif
		banksel OPTION_REG ; select SFR bank
		clrf	OPTION_REG
		bsf		OPTION_REG, NOT_WPUEN
		bsf		OPTION_REG, PSA
		banksel	INTCON
		clrf	INTCON
#if !DEBUG
		; Call interrupt routine if RADET changes
		banksel	IOCAP
		clrf	IOCAP
		bsf		IOCAP, NORFDET
		banksel	IOCAN
		clrf	IOCAN
		bsf		IOCAN, NORFDET
		banksel	INTCON
		bsf		INTCON, IOCIE
		; Allow Global Interrupts
		bsf		INTCON, GIE
		
#endif
		banksel	PORTA			; Make sure we are using bank 0
		clrf 	STATUS 			; ensure file register bank set to 0
		call	i2c_init
;;;;;;;;;;;;;;;;;;		
main_loop
;;;;;;;;;;;;;;;;;;

		banksel	PORTA
		btfsc	PORTA, NORFDET	; Sense is flipped by 2N3904 Transistor
		goto	do_int_ref	; RF is not detected
		goto	do_ext_ref	; RF is detected

do_ext_ref

  #if  ARDUINO_VAL

		WRITE_REG 0x03, 0xFE
		WRITE_REG 0x0F, 0x04

		WRITE_REG 0x10, 0x0C	; Register 16
		WRITE_REG 0x11, 0x8C
		WRITE_REG 0x12, 0x8C
		WRITE_REG 0x13, 0x8C
		WRITE_REG 0x14, 0x8C
		WRITE_REG 0x15, 0x8C
		WRITE_REG 0x16, 0x8C
		WRITE_REG 0x17, 0x8C

		WRITE_REG 0x18, 0xA8
		WRITE_REG 0x19, 0xAA

		WRITE_REG 0x1A, 0x00
		WRITE_REG 0x1B, 0x01
		WRITE_REG 0x1C, 0x00
		WRITE_REG 0x1D, 0x26
		WRITE_REG 0x1E, 0x00
		WRITE_REG 0x1F, 0x00
		WRITE_REG 0x20, 0x00
		WRITE_REG 0x21, 0x00

		WRITE_REG 0x22, 0x00
		WRITE_REG 0x23, 0x01
		WRITE_REG 0x24, 0x00
		WRITE_REG 0x25, 0x26
		WRITE_REG 0x26, 0x00
		WRITE_REG 0x27, 0x00
		WRITE_REG 0x28, 0x00
		WRITE_REG 0x29, 0x00

		WRITE_REG 0x2A, 0x42
		WRITE_REG 0x2B, 0x40
		WRITE_REG 0x2C, 0x00
		WRITE_REG 0x2D, 0x0F
		WRITE_REG 0x2E, 0xAD
		WRITE_REG 0x2F, 0xFE
		WRITE_REG 0x30, 0xC0
		WRITE_REG 0x31, 0xC0

		WRITE_REG 0xA2, 0x00
		WRITE_REG 0xA3, 0x00
		WRITE_REG 0xA4, 0x00
		WRITE_REG 0xB1, 0x80
		WRITE_REG 0xB7, 0x12

#if RESET_PLL
;C 	// Reset the PLL. This causes a glitch in the output. For small changes to 
;C 	// the parameters, you don't need to reset the PLL, and there is no glitch
;C 	i2cSendRegister(SI_PLL_RESET, 0xA0);	
		movlw	SI_PLL_RESET
		movwf	i2caddr
		movlw	0xA0
		movwf	i2cdata
		call 	i2cSendRegister
#endif

		call	i2c_exit

  #else

	    WRITE_REG 0x02, 0x4B
	    WRITE_REG 0x03, 0x00
	    WRITE_REG 0x04, 0x20
	    WRITE_REG 0x07, 0x01
	    WRITE_REG 0x0F, 0x04

	    WRITE_REG 0x10, 0x0C
	    WRITE_REG 0x11, 0x8C
	    WRITE_REG 0x12, 0x8C
	    WRITE_REG 0x13, 0x8C
	    WRITE_REG 0x14, 0x8C
	    WRITE_REG 0x15, 0x8C
	    WRITE_REG 0x16, 0x8C
	    WRITE_REG 0x17, 0x8C

		WRITE_REG 0x18, 0xA8
		WRITE_REG 0x19, 0xAA

	    WRITE_REG 0x1A, 0x01
	    WRITE_REG 0x1B, 0x40
	    WRITE_REG 0x1C, 0x00
	    WRITE_REG 0x1D, 0x2A
	    WRITE_REG 0x1E, 0xF7
	    WRITE_REG 0x1F, 0x00
	    WRITE_REG 0x20, 0x00
	    WRITE_REG 0x21, 0xC0
	    WRITE_REG 0x2A, 0x00
	    WRITE_REG 0x2B, 0x04
	    WRITE_REG 0x2C, 0x00
	    WRITE_REG 0x2D, 0x11
	    WRITE_REG 0x2E, 0xE0
	    WRITE_REG 0x2F, 0x00
	    WRITE_REG 0x30, 0x00
	    WRITE_REG 0x31, 0x00
	    WRITE_REG 0x5A, 0x00
	    WRITE_REG 0x5B, 0x00
	    WRITE_REG 0x95, 0x00
	    WRITE_REG 0x96, 0x00
	    WRITE_REG 0x97, 0x00
	    WRITE_REG 0x98, 0x00
	    WRITE_REG 0x99, 0x00
	    WRITE_REG 0x9A, 0x00
	    WRITE_REG 0x9B, 0x00
	    WRITE_REG 0xA2, 0x00
	    WRITE_REG 0xA3, 0x00
	    WRITE_REG 0xA4, 0x00
	    WRITE_REG 0xA5, 0x00
	    WRITE_REG 0xB7, 0x12

#if RESET_PLL
;C 	// Reset the PLL. This causes a glitch in the output. For small changes to 
;C 	// the parameters, you don't need to reset the PLL, and there is no glitch
;C 	i2cSendRegister(SI_PLL_RESET, 0xA0);	
		movlw	SI_PLL_RESET
		movwf	i2caddr
		movlw	0xA0
		movwf	i2cdata
		call 	i2cSendRegister
#endif

		call	i2c_exit

  #endif

	goto done


;  For INT reference - 27 MHz
do_int_ref

  #if  ARDUINO_VAL

		WRITE_REG 0x03, 0xFE
		WRITE_REG 0x0F, 0x00

		WRITE_REG 0x10, 0x0C	; Register 16
		WRITE_REG 0x11, 0x8C
		WRITE_REG 0x12, 0x8C
		WRITE_REG 0x13, 0x8C
		WRITE_REG 0x14, 0x8C
		WRITE_REG 0x15, 0x8C
		WRITE_REG 0x16, 0x8C
		WRITE_REG 0x17, 0x8C

		WRITE_REG 0x18, 0xA8
		WRITE_REG 0x19, 0xAA

		WRITE_REG 0x1A, 0x42
		WRITE_REG 0x1B, 0x40
		WRITE_REG 0x1C, 0x00
		WRITE_REG 0x1D, 0x0C
		WRITE_REG 0x1E, 0xD0
		WRITE_REG 0x1F, 0xF9
		WRITE_REG 0x20, 0x0A
		WRITE_REG 0x21, 0x80

		WRITE_REG 0x22, 0x42
		WRITE_REG 0x23, 0x40
		WRITE_REG 0x24, 0x00
		WRITE_REG 0x25, 0x0C	
		WRITE_REG 0x26, 0xD0
		WRITE_REG 0x27, 0xF9
		WRITE_REG 0x28, 0x0A
		WRITE_REG 0x29, 0x80

		WRITE_REG 0x2A, 0x42
		WRITE_REG 0x2B, 0x40
		WRITE_REG 0x2C, 0x00
		WRITE_REG 0x2D, 0x0F
		WRITE_REG 0x2E, 0xAD
		WRITE_REG 0x2F, 0xFE
		WRITE_REG 0x30, 0xC0
		WRITE_REG 0x31, 0xC0

		WRITE_REG 0xA2, 0x00
		WRITE_REG 0xA3, 0x00
		WRITE_REG 0xA4, 0x00
		WRITE_REG 0xB1, 0x80
		WRITE_REG 0xB7, 0x92

#if RESET_PLL
;C 	// Reset the PLL. This causes a glitch in the output. For small changes to 
;C 	// the parameters, you don't need to reset the PLL, and there is no glitch
;C 	i2cSendRegister(SI_PLL_RESET, 0xA0);	
		movlw	SI_PLL_RESET
		movwf	i2caddr
		movlw	0xA0
		movwf	i2cdata
		call 	i2cSendRegister
#endif

		call	i2c_exit

  #else

	    WRITE_REG 0x02, 0x53
	    WRITE_REG 0x03, 0x00
	    WRITE_REG 0x04, 0x20
	    WRITE_REG 0x07, 0x01
	    WRITE_REG 0x0F, 0x00

		WRITE_REG 0x10, 0x0C	; Register 16
		WRITE_REG 0x11, 0x8C
		WRITE_REG 0x12, 0x8C
		WRITE_REG 0x13, 0x8C
		WRITE_REG 0x14, 0x8C
		WRITE_REG 0x15, 0x8C
		WRITE_REG 0x16, 0x8C
		WRITE_REG 0x17, 0x8C

		WRITE_REG 0x18, 0xA8
		WRITE_REG 0x19, 0xAA

	    WRITE_REG 0x1A, 0x01
	    WRITE_REG 0x1B, 0x20
	    WRITE_REG 0x1C, 0x00
	    WRITE_REG 0x1D, 0x0E
	    WRITE_REG 0x1E, 0xA7
	    WRITE_REG 0x1F, 0x00
	    WRITE_REG 0x20, 0x00
	    WRITE_REG 0x21, 0xA0

	    WRITE_REG 0x2A, 0x00
	    WRITE_REG 0x2B, 0x04
	    WRITE_REG 0x2C, 0x00
	    WRITE_REG 0x2D, 0x11
	    WRITE_REG 0x2E, 0xE0
	    WRITE_REG 0x2F, 0x00
	    WRITE_REG 0x30, 0x00
	    WRITE_REG 0x31, 0x00

	    WRITE_REG 0x5A, 0x00
	    WRITE_REG 0x5B, 0x00
	    WRITE_REG 0x95, 0x00
	    WRITE_REG 0x96, 0x00
	    WRITE_REG 0x97, 0x00
	    WRITE_REG 0x98, 0x00
	    WRITE_REG 0x99, 0x00
	    WRITE_REG 0x9A, 0x00
	    WRITE_REG 0x9B, 0x00
	    WRITE_REG 0xA2, 0x00
	    WRITE_REG 0xA3, 0x00
	    WRITE_REG 0xA4, 0x00
	    WRITE_REG 0xA5, 0x00
	    WRITE_REG 0xB7, 0x92

#if RESET_PLL
;C 	// Reset the PLL. This causes a glitch in the output. For small changes to 
;C 	// the parameters, you don't need to reset the PLL, and there is no glitch
;C 	i2cSendRegister(SI_PLL_RESET, 0xA0);	
		movlw	SI_PLL_RESET
		movwf	i2caddr
		movlw	0xA0
		movwf	i2cdata
		call 	i2cSendRegister
#endif

		call	i2c_exit
  #endif

		goto 	done

done

#if DEBUG
		call	blink5
#endif

		sleep

		call	wait_half_sec
		goto	main_loop


;C //
;C // Switches off Si5351a output
;C // Example: si5351aOutputOff with W = SI_CLK0_CONTROL
;C // will switch off output CLK0
;C //
;C void si5351aOutputOff(uint8_t clk)
;C {
si5351aOutputOff
		call i2c_init
;C 	i2cSendRegister(clk, 0x80);		// Refer to SiLabs AN619 to see bit values - 0x80 turns off the output stage
		movwf	i2caddr
		movlw	0x80
		movwf	i2cdata
		call	i2cSendRegister
;C 	i2c_exit();
		call	i2c_exit
		return


;*************************************************************************
; Issues a repeated start condition and sends address and transfer direction.
; return 0 = device accessible, 1= failed to access device
;
; uint8_t i2cSendRegister(uint8_t reg, uint8_t data)
;	addr = i2caddr, data = i2cdata return = W 
;*************************************************************************
i2cSendRegister
		movlw	I2C_WRITE
		call	i2c_start_wait
		movfw	i2caddr
		call	i2c_write
		iorlw	0
		btfss	STATUS, Z
		goto 	return3		; Not zero
		movfw	i2cdata
		call	i2c_write
		call 	i2c_stop
		retlw	0
return3
;		call	blink3
		call 	i2c_stop
		retlw	3
return4
;		call	blink4
		call 	i2c_stop
		retlw	4

;*************************************************************************
; Issues a repeated start condition and sends address and transfer direction.
; return 0 = device accessible, 1= failed to access device
;
; uint8_t  i2cReadRegister(unsigned char addr);
;	addr = I2CADDR, data = I2CDATA return = W 
;*************************************************************************
i2cReadRegister
		movlw	I2C_WRITE
		call	i2c_start_wait
		movfw	i2caddr
		call	i2c_write
		addlw	0
		btfss	STATUS, Z
		goto 	rreturn3		; Not zero
		movlw	I2C_READ
		call	i2c_rep_start
		addlw	0
		btfss	STATUS, Z
		goto	rreturn4		; Not zero
		call	i2c_readNak
		movwf	i2cdata
		call 	i2c_stop
		retlw	0
rreturn3
;		call	blink3
		retlw	3
rreturn4
;		call	blink4
		retlw	4

shortdelay                      ; A short delay 
i2c_delay_T2
	return ;;;
	 ; delay 100.0 microsec

		goto	dly1	; 4 us
dly1					
		goto	dly2	; 4 us
dly2
		goto	dly3	; 4 us
dly3
		goto	dly4	; 4 us
dly4
		goto	dly5	; 4 us
dly5
		goto	dly6	; 4 us
dly6
		goto	dly7	; 4 us
dly7
		goto	dly8	; 4 us
dly8
		goto	dly9	; 4 us
dly9
		goto	dly10	; 4 us
dly10
        return

wait1sec
		movwf	sav_w
		movfw	STATUS
		movwf	sav_status
		movlw	20
		movwf	slow_timer1
wait50msec
		movlw	100
		movwf	slow_timer2
waitsec0		; this chain takes 200 us
		goto	waitsec1	; 4 us
waitsec1					
		goto	waitsec2	; 4 us
waitsec2
		goto	waitsec3	; 4 us
waitsec3
		goto	waitsec4	; 4 us
waitsec4
		goto	waitsec5	; 4 us
waitsec5
		goto	waitsec6	; 4 us
waitsec6
		goto	waitsec7	; 4 us
waitsec7
		goto	waitsec8	; 4 us
waitsec8
		goto	waitsec9	; 4 us
waitsec9
		goto	waitsec10	; 4 us
waitsec10
		goto	waitsec11	; 4 us
waitsec11					
		goto	waitsec12	; 4 us
waitsec12
		goto	waitsec13	; 4 us
waitsec13
		goto	waitsec14	; 4 us
waitsec14
		goto	waitsec15	; 4 us
waitsec15
		goto	waitsec16	; 4 us
waitsec16
		goto	waitsec17	; 4 us
waitsec17
		goto	waitsec18	; 4 us
waitsec18
		goto	waitsec19	; 4 us
waitsec19
		goto	waitsec20	; 4 us
waitsec20
		goto	waitsec21	; 4 us
waitsec21					
		goto	waitsec22	; 4 us
waitsec22
		goto	waitsec23	; 4 us
waitsec23
		goto	waitsec24	; 4 us
waitsec24
		goto	waitsec25	; 4 us
waitsec25
		decfsz	slow_timer2,f
		goto	waitsec0
		decfsz	slow_timer1,f
		goto	wait50msec
		movfw	sav_status
		movwf	STATUS
		swapf 	sav_w,f ;
		swapf 	sav_w,w ; restore W register contents
		return

wait_half_sec
		movwf	sav_w
		movfw	STATUS
		movwf	sav_status
		movlw	10
		movwf	slow_timer1
		goto	wait50msec

#if DEBUG

;*************************************************************************
; LED routines for debug
;*************************************************************************
; LED routines
		; Test LED
blink7	LED_ON
		call wait1sec
		LED_OFF
		call wait1sec
blink6	LED_ON
		call wait1sec
		LED_OFF
		call wait1sec
blink5	LED_ON
		call wait1sec
		LED_OFF
		call wait1sec
blink4	LED_ON
		call wait1sec
		LED_OFF
		call wait1sec
blink3	LED_ON
		call wait1sec
		LED_OFF
		call wait1sec
blink2	LED_ON
		call wait1sec
		LED_OFF
		call wait1sec
blink1
		LED_ON
		call wait1sec
		LED_OFF
		call wait1sec
		call wait1sec
		call wait1sec
		return

blink5fast	
		LED_ON
		call wait_half_sec
		LED_OFF
		call wait_half_sec
blink4fast
		LED_ON
		call wait_half_sec
		LED_OFF
		call wait_half_sec
blink3fast
		LED_ON
		call wait_half_sec
		LED_OFF
		call wait_half_sec
blink2fast
		LED_ON
		call wait_half_sec
		LED_OFF
		call wait_half_sec
blink1fast
		LED_ON
		call wait_half_sec
		LED_OFF
		call wait1sec
		call wait1sec
		return

;*************************************************************************
; Display register W in hex on LED
;*************************************************************************
blink_hex
		movwf	sav_w_hex
		movfw 	STATUS ; move status register into W register
		movwf 	sav_status_hex ; save off contents of STATUS register

dobit1
		movfw	sav_w_hex
		andlw	0x80
		btfss	STATUS,Z
		goto	blink_r1
;		blink 3 fast
		call 	blink3fast
		goto	dobit2
blink_r1
;		blink 5 fast
		call 	blink5fast
		goto	dobit2
dobit2
		movfw	sav_w_hex
		andlw	0x40
		btfss	STATUS,Z
		goto	blink_r2
;		blink 3 fast
		call 	blink3fast
		goto	dobit3
blink_r2
;		blink 5 fast
		call 	blink5fast
		goto	dobit3
dobit3
		movfw	sav_w_hex
		andlw	0x20
		btfss	STATUS,Z
		goto	blink_r3
;		blink 3 fast
		call 	blink3fast
		goto	dobit4
blink_r3
;		blink 5 fast
		call 	blink5fast
		goto	dobit4
dobit4
		movfw	sav_w_hex
		andlw	0x10
		btfss	STATUS,Z
		goto	blink_r4
;		blink 3 fast
		call 	blink3fast
		goto	dobit5
blink_r4
;		blink 5 fast
		call 	blink5fast
		goto	dobit5
dobit5
		movfw	sav_w_hex
		andlw	0x08
		btfss	STATUS,Z
		goto	blink_r5
;		blink 3 fast
		call 	blink3fast
		goto	dobit6
blink_r5
;		blink 5 fast
		call 	blink5fast
		goto	dobit6
dobit6
		movfw	sav_w_hex
		andlw	0x04
		btfss	STATUS,Z
		goto	blink_r6
;		blink 3 fast
		call 	blink3fast
		goto	dobit7
blink_r6
;		blink 5 fast
		call 	blink5fast
		goto	dobit7
dobit7
		movfw	sav_w_hex
		andlw	0x02
		btfss	STATUS,Z
		goto	blink_r7
;		blink 3 fast
		call 	blink3fast
		goto	dobit8
blink_r7
;		blink 5 fast
		call 	blink5fast
		goto	dobit8
dobit8
		movfw	sav_w_hex
		andlw	0x01
		btfss	STATUS,Z
		goto	blink_r8
;		blink 3 fast
		call 	blink3fast
		goto	dobit9
blink_r8
;		blink 5 fast
		call 	blink5fast
		goto	dobit9
dobit9
		movfw	sav_status_hex
		movwf	STATUS
		swapf 	sav_w_hex,f ;
		swapf 	sav_w_hex,w ; restore W register contents
		return

#endif

;*************************************************************************	
; This code works by initially setting SDA and SCL to low.
; To toggle value back from low to high to low the code changes SDA and SCL
; from output to input back to output.  Both SDA and SCL have pullup resistors
; so when they are input they will appear to be high.  This prevents the 
; possibility that there is contention from the SLAVE or from another MASTER 
; trying to force SDA or SCL low while we are trying to force them high
;*************************************************************************

;*************************************************************************
; Initialization of the I2C bus interface.
; 
; extern void i2c_init(void)
;*************************************************************************
i2c_init
        BANKSEL I2CTRIS
        bsf     I2CTRIS,SDA		; SDA input (high)
        bsf     I2CTRIS,SCL		; SCL input (high)
        BANKSEL I2CPORT
		bcf		I2CPORT,SDA		; SDA := LOW
		bcf		I2CPORT,SCL		; SCL := LOW
		SETHIGH	SCL				; Issue Stop - Cylce 16 times
		SETLOW	SCL				; Issue 1
		SETHIGH	SCL				; 
		SETLOW	SCL				; Issue 2
		SETHIGH	SCL				; 
		SETLOW	SCL				; Issue 3
		SETHIGH	SCL				; 
		SETLOW	SCL				; Issue 4
		SETHIGH	SCL				; 
		SETLOW	SCL				; Issue 5
		SETHIGH	SCL				; 
		SETLOW	SCL				; Issue 6
		SETHIGH	SCL				; 
		SETLOW	SCL				; Issue 7
		SETHIGH	SCL				; 
		SETLOW	SCL				; Issue 8
		SETHIGH	SCL				; 
		SETLOW	SCL				; Issue 9
		SETHIGH	SCL				; 
		SETLOW	SCL				; Issue 10
		SETHIGH	SCL				; 
		SETLOW	SCL				; Issue 11
		SETHIGH	SCL				; 
		SETLOW	SCL				; Issue 12
		SETHIGH	SCL				; 
		SETLOW	SCL				; Issue 13
		SETHIGH	SCL				; 
		SETLOW	SCL				; Issue 14
		SETHIGH	SCL				; 
		SETLOW	SCL				; Issue 15
		SETHIGH	SCL				; 
		SETLOW	SCL				; Issue 16
		SETHIGH	SCL				; 
		SETLOW	SCL				; 
        SETLOW	SDA				; SDA output (low)
		SETHIGH	SCL				; Force Stop
		SETHIGH	SDA
		SETLOW	SCL				;
		SETHIGH	SCL				; 
		return

;*************************************************************************
; Release of the I2C bus SDA pin directions - make it outputs again, after use
; 
; extern void i2c_init(void)
;*************************************************************************
i2c_exit
        SETLOW	SDA		; SDA output (low)
		return

;*************************************************************************	
; Issues a start condition and sends address and transfer direction.
; return 0 = device accessible, 1= failed to access device
;
; extern unsigned char i2c_start(unsigned char addr);
;	addr = W, return = W
;*************************************************************************

i2c_start
		SETLOW  SDA		; SDA output (low)
		call	i2c_write		; write address
		return


;*************************************************************************
; Issues a repeated start condition and sends address and transfer direction.
; return 0 = device accessible, 1= failed to access device
;
; extern unsigned char i2c_rep_start(unsigned char addr);
;	addr = W,  return = W
;*************************************************************************

i2c_rep_start
		SETLOW  SCL				; SCL output (low)
		SETHIGH SDA				; SDA input (high)
		SETHIGH SCL				; SCL input (high)
		SETLOW  SDA				; SDA output (low)
		call	i2c_write		; write address
		return


;*************************************************************************	
; Issues a start condition and sends address and transfer direction.
; If device is busy, use ack polling to wait until device is ready
;
; extern void i2c_start_wait(unsigned char addr);
;	addr = W
;*************************************************************************

i2c_start_wait
		movwf	tmp				; Save W in tmp
i2c_start_wait1
		SETLOW  SCL				; SCL output (low) ; Send Start
		SETHIGH SDA				; SDA input (high) ; Send Start
		SETHIGH SCL				; SCL input (high) ; Send Start
		SETLOW  SDA				; SDA output (low) ; Send Start
		movfw	tmp
		call 	i2c_write		; write address
		iorlw	0
		btfsc	STATUS, Z		; if device not busy -> done
		goto	i2c_start_wait_done	; Is zero
		call	i2c_stop		; terminate write operation
		goto	i2c_start_wait1	; device busy, poll ack again
i2c_start_wait_done
		return


;*************************************************************************
; Terminates the data transfer and releases the I2C bus
;
; extern void i2c_stop(void)
;*************************************************************************

i2c_stop
		SETLOW  SCL				; SCL output (low)
		SETLOW  SDA				; SDA output (low)
		SETHIGH SCL				; SCL input (high)
		SETHIGH SDA				; SDA input (high)
		return


;*************************************************************************
; Send one byte to I2C device
; return 0 = write successful, 1 = write failed
;
; extern unsigned char i2c_write( unsigned char data );
;	data = W,  return = W
;*************************************************************************
i2c_write
		movwf	tmpwr
		bsf		STATUS, C			; set carry flag
		rlf 	tmpwr, F			; shift in carry and out bit one
		movf	tmpwr, F			; Set Z bit if appropriate - should never be set.	
		goto	i2c_write_first
i2c_write_bit
		lslf	tmpwr, F			; if transmit register empty
i2c_write_first
		btfsc	STATUS, Z		
		goto	i2c_get_ack
		SETLOW  SCL				; SCL output (low)
;	put data on SDA
		btfss	STATUS, C
		goto	i2c_write_low	; Not zero
		SETHIGH SDA				; SDA input (high)
		goto	i2c_write_high
i2c_write_low
		SETLOW  SDA				; SDA output (low)
		goto	i2c_write_high
i2c_write_high
		SETHIGH SCL				; SCL input (high) - sample SDA
		goto	i2c_write_bit
	
i2c_get_ack
		SETLOW  SCL				; SCL output (low)  - Finish SDA sample
		SETHIGH SDA				; release SDA input (high)
		SETHIGH SCL				; SCL input (high) - read SDA
i2c_ack_wait
        BANKSEL I2CPORT
		btfss	I2CPORT,SCL		; Skip if SCL high
		goto	i2c_ack_wait	; wait SCL high (in case wait states are inserted)
		btfsc	I2CPORT,SDA		; if SDA high -> return 1
		goto	i2c_nak
; Wait for slave to release SDA line
;		call	blink2fast
		SETLOW	SCL
		retlw	0
i2c_nak
;		call	blink2
		SETLOW	SCL
		retlw	1

#if 0
;*************************************************************************
; Send one byte to I2C device
; return 0 = write successful, 1 = write failed
;
; extern unsigned char i2c_write( unsigned char data );
;	data = W,  return = W
;*************************************************************************
i2c_write1
		movwf	tmpwr
		bsf		STATUS, C			; set carry flag
		rlf 	tmpwr, F			; shift in carry and out bit one
		goto	i2c_write_first1
i2c_write_bit1
		lslf	tmpwr, F			; if transmit register empty
i2c_write_first1
		btfsc	STATUS, Z		
		goto	i2c_get_ack1
		SETLOW  SCL				; SCL output (low)
;	put data on SDA
		btfss	STATUS, C
		goto	i2c_write_low1	; Not zero
		SETHIGH SDA				; SDA input (high)
		goto	i2c_write_high1
i2c_write_low1
		SETLOW  SDA				; SDA output (low)
		goto	i2c_write_high1
i2c_write_high1
		SETHIGH SCL				; SCL input (high) - sample SDA
		goto	i2c_write_bit1
	
i2c_get_ack1
		SETLOW  SCL				; SCL output (low)  - Finish SDA sample
		SETHIGH SDA				; SDA input (high)
		SETHIGH SCL				; SCL input (high) - read SDA
i2c_ack_wait1
        BANKSEL I2CPORT
		btfss	I2CPORT,SCL		; Skip if SCL high
		goto	i2c_ack_wait1	; wait SCL high (in case wait states are inserted)
		btfsc	I2CPORT,SDA		; if SDA high -> return 1
		goto	i2c_nak1
;		call	blink3fast
		retlw	0
i2c_nak1
;		call	blink3
		goto	i2c_write1	; try again
		retlw	1
#endif

;*************************************************************************
; read one byte from the I2C device, send ack or nak to device
; (ack=1, send ack, request more data from device 
;  ack=0, send nak, read is followed by a stop condition)
;
; extern unsigned char i2c_read(unsigned char ack);
;	ack = W
; extern unsigned char i2c_readAck(void);
; extern unsigned char i2c_readNak(void);
; 	return = W
;*************************************************************************
i2c_readNak
		clrw
		goto	i2c_read
i2c_readAck
		movlw	1
i2c_read
		movwf	com
		clrf	tmp
		incf	tmp,F			; data = 0x01
i2c_read_bit
		SETLOW  SCL				; SCL output (low)
		SETHIGH SDA				; SDA input (high) (from previous ACK)
	
		SETHIGH SCL				; SCL output (low)
	
        BANKSEL I2CPORT
i2c_read_stretch
		btfss	I2CPORT,SCL		; loop until SCL is high (allow slave to stretch SCL)
		goto	i2c_read_stretch
    	
		bcf		STATUS, C		; clear carry flag
		btfsc	I2CPORT,SDA		; if SDA is high
		bsf		STATUS, C		;    set carry flag
	
		rlf		tmp,F			; store bit
		btfss	STATUS, C
		goto	i2c_read_bit	; while receive register not full
	
i2c_put_ack
		SETLOW  SCL				; SCL output (low)	
		movf	tmp,F
		btfsc	STATUS, Z
		goto	i2c_put_ack_low	; if (ack=0)
		SETHIGH SDA				;   SDA input (high)
		goto	i2c_put_ack_high
i2c_put_ack_low                	; else
		SETLOW  SDA				;   SDA output (low)
i2c_put_ack_high
		SETHIGH SCL				; SCL input (high)
        BANKSEL I2CPORT
i2c_put_ack_wait
		btfss	I2CPORT,SCL		; loop until SCL is high
		goto	i2c_put_ack_wait
		movfw	tmp
		return

	END ; required directive
