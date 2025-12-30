; PROJE :    Curtain Control System (Board #2)
; HAZIRLAYANLAR: YUNUS EMRE AYCIBIN & ZEYNEP SILA TOSUN
; TARIH:         2025

    LIST P=16F877A
    INCLUDE "P16F877A.INC"

    ; --- KONFIGURASYON (Sigorta) AYARLARI ---
    __CONFIG _FOSC_XT & _WDTE_OFF & _PWRTE_ON & _BOREN_OFF & _LVP_OFF & _CPD_OFF & _WRT_OFF & _CP_OFF

    ; --- DEGISKEN TANIMLAMALARI (RAM - BANK 0) ---
    CBLOCK 0x20
        ; Motor Degiskenleri
        PHASE       ; Step motorun hangi adimda oldugu
        CUR_L, CUR_H; Motorun su anki konumu 
        TAR_L, TAR_H; Motorun gitmesi gereken hedef 
        
        ; Sensor Degiskenleri
        LDR_VAL     ; Isik sensoru degeri
        POT_VAL     ; Potansiyometre degeri
        LAST_POT    ; Potansiyometrenin bir onceki degeri
        PERDE_YZD   ; Perdenin aciklik yuzdesi (%)

        ; LCD Format Degiskenleri
        TEMP_INT    ; Sicaklik Tam Sayi
        TEMP_FRAC   ; Sicaklik Ondalik
        PRES_H      ; Basinc Yuksek Byte
        PRES_L      ; Basinc Dusuk Byte
        
        ; Hesaplama ve Ekran Degiskenleri
        D1, D2, LCD_VAR, TEMP_PORT
        MATH_L, MATH_H 
        SAYI_L, YUZLER, ONLAR, BIRLER
        
        ; Sistem Degiskenleri
        LCD_SAYAC   ; Ekran yenileme sayaci
        W_TEMP      ; Kesme W yedegi
        STATUS_TEMP ; Kesme STATUS yedegi
        RX_DATA     ; UART Gelen Veri
    ENDC

    ; --- PROGRAM BASLANGICI ---
    ORG 0x000
    GOTO SETUP      ; Ayarlara git

    ; ==========================================================================
    ; KESME (INTERRUPT) BOLUMU - SERI HABERLESME
    ; ==========================================================================
    ORG 0x004
    ; 1. Yedekleme
    MOVWF W_TEMP        
    SWAPF STATUS, W     
    MOVWF STATUS_TEMP   
    
    ; 2. Bank 0'a gec (Guvenlik icin)
    BCF STATUS, RP0
    BCF STATUS, RP1

    ; 3. Veri Geldi mi Kontrolu
    BTFSS PIR1, RCIF    ; Veri yoksa cik
    GOTO INT_EXIT       
    
    ; 4. Veriyi Oku
    MOVF RCREG, W       
    MOVWF RX_DATA       
    
    ; --- KOMUT KONTROL ZINCIRI ---
    
    ; KONTROL 1: PC '01' gonderdi mi? (Hedef Perde Low Byte)
    MOVLW 0x01
    SUBWF RX_DATA, W
    BTFSC STATUS, Z     ; Sonuc 0 ise (Esitse)
    GOTO SEND_TAR_L     
    
    ; KONTROL 2: PC '02' gonderdi mi? (Hedef Perde High Byte)
    MOVLW 0x02
    SUBWF RX_DATA, W
    BTFSC STATUS, Z
    GOTO SEND_TAR_H

    ; KONTROL 3: PC '07' gonderdi mi? (Isik Siddeti)
    MOVLW 0x07
    SUBWF RX_DATA, W
    BTFSC STATUS, Z
    GOTO SEND_LDR

    ; Hicbiri degilse cik
    GOTO INT_EXIT

; --- UART GONDERME ISLEMLERI (INT ICINDE) ---
SEND_TAR_L
    MOVF TAR_L, W       ; Hedef Low'u W'ye al
    CALL UART_TX_ISR    ; Gonder
    GOTO INT_EXIT

SEND_TAR_H
    MOVF TAR_H, W       ; Hedef High'i W'ye al
    CALL UART_TX_ISR    ; Gonder
    GOTO INT_EXIT

SEND_LDR
    MOVF LDR_VAL, W     ; LDR Degerini W'ye al
    CALL UART_TX_ISR    ; Gonder
    GOTO INT_EXIT

INT_EXIT
    ; 5. Yedekleri Geri Yukle ve Cik
    SWAPF STATUS_TEMP, W
    MOVWF STATUS        
    SWAPF W_TEMP, F
    SWAPF W_TEMP, W     
    RETFIE              

    ; ==========================================================================
    ; SISTEM AYARLARI (SETUP)
    ; ==========================================================================
SETUP
    BSF STATUS, RP0     ; Bank 1
    
    ; Port Ayarlari
    CLRF TRISB          ; LCD Cikis
    CLRF TRISD          ; Motor Cikis
    MOVLW 0xFF
    MOVWF TRISA         ; Sensor Giris
    
    ; UART Ayarlari (Bank 1)
    BSF TRISC, 7        ; RX Giris
    BCF TRISC, 6        ; TX Cikis
    MOVLW d'25'         ; 9600 Baud
    MOVWF SPBRG
    MOVLW b'00100100'   ; TXEN=1, BRGH=1
    MOVWF TXSTA
    BSF PIE1, RCIE      ; RX Kesmesi Aktif
    
    ; ADC Ayarlari (Bank 1)
    MOVLW b'00000100'   
    MOVWF ADCON1
    
    BCF STATUS, RP0     ; Bank 0'a don
    
    ; UART Alim Acma (Bank 0)
    MOVLW b'10010000'   ; SPEN=1, CREN=1
    MOVWF RCSTA
    
    ; Kesme Izinleri
    BSF INTCON, GIE     ; Global Interrupt
    BSF INTCON, PEIE    ; Peripheral Interrupt
    
    ; ADC Acma (Bank 0)
    MOVLW b'10000001'   
    MOVWF ADCON0
    
    ; Degisken Sifirlama
    CLRF PORTB
    CLRF PORTD
    CLRF CUR_L
    CLRF CUR_H
    CLRF TAR_L
    CLRF TAR_H
    CLRF LAST_POT
    
    ; --- VARSAYILAN SENSOR DEGERLERI (Simulasyon) ---
    MOVLW d'25'
    MOVWF TEMP_INT
    MOVLW d'5'
    MOVWF TEMP_FRAC
    MOVLW d'3'
    MOVWF PRES_H
    MOVLW d'245'
    MOVWF PRES_L
    
    CALL LCD_INIT       ; Ekrani Baslat
    GOTO MAIN

    ; ==========================================================================
    ; ANA DONGU
    ; ==========================================================================
MAIN
    ; 1. ISIK KONTROLU
    CALL READ_LDR
    MOVLW d'128'        ; Esik Deger
    SUBWF LDR_VAL, W
    BTFSC STATUS, C     ; LDR > 128 mi?
    GOTO MOD_GECE       ; Evet -> Gece Modu

MOD_GUNDUZ
    ; 2. POT KONTROLU
    CALL READ_POT
    
    ; Gurultu Filtresi
    MOVF POT_VAL, W
    ANDLW b'11111100'
    MOVWF D1
    MOVF LAST_POT, W
    ANDLW b'11111100'
    SUBWF D1, W
    BTFSC STATUS, Z     ; Degisim yoksa atla
    GOTO HAREKET
    
    MOVF POT_VAL, W
    MOVWF LAST_POT
    
    ; Pot (0-255) -> Motor (0-1000) Cevrimi
    MOVF POT_VAL, W
    MOVWF TAR_L
    CLRF TAR_H
    BCF STATUS, C
    RLF TAR_L, F        ; x2
    RLF TAR_H, F
    BCF STATUS, C
    RLF TAR_L, F        ; x4
    RLF TAR_H, F
    GOTO HAREKET

MOD_GECE
    MOVLW 0xE8          ; 1000 Adim (Low)
    MOVWF TAR_L
    MOVLW 0x03          ; 1000 Adim (High)
    MOVWF TAR_H
    GOTO HAREKET

    ; ==========================================================================
    ; MOTOR SURME
    ; ==========================================================================
HAREKET
    MOVF TAR_H, W
    SUBWF CUR_H, W
    BTFSS STATUS, Z
    GOTO CHK_DIR
    MOVF TAR_L, W
    SUBWF CUR_L, W
    BTFSC STATUS, Z
    GOTO UPDATE         ; Hedefe ulasildi
    BTFSS STATUS, C
    GOTO FWD
    GOTO BCK

CHK_DIR
    BTFSS STATUS, C
    GOTO FWD
    GOTO BCK

FWD
    CALL STEP_CW
    INCF CUR_L, F
    BTFSC STATUS, Z
    INCF CUR_H, F
    GOTO UPDATE

BCK
    CALL STEP_CCW
    MOVLW 1
    SUBWF CUR_L, F
    BTFSS STATUS, C
    DECF CUR_H, F
    GOTO UPDATE

    ; ==========================================================================
    ; GUNCELLEME
    ; ==========================================================================
UPDATE
    CALL CALC_REAL_PERCENT
    CALL DELAY_M
    DECFSZ LCD_SAYAC, F
    GOTO MAIN
    
    CALL LCD_REFRESH
    MOVLW d'10'
    MOVWF LCD_SAYAC
    GOTO MAIN

; --- YARDIMCI ALT PROGRAMLAR ---

CALC_REAL_PERCENT
    CLRF PERDE_YZD
    MOVF CUR_L, W
    MOVWF MATH_L
    MOVF CUR_H, W
    MOVWF MATH_H
DIV_LOOP
    MOVF MATH_H, F
    BTFSS STATUS, Z
    GOTO DO_SUB
    MOVLW d'10'
    SUBWF MATH_L, W
    BTFSS STATUS, C
    GOTO DIV_END
DO_SUB
    MOVLW d'10'
    SUBWF MATH_L, F
    BTFSS STATUS, C
    DECF MATH_H, F
    INCF PERDE_YZD, F
    GOTO DIV_LOOP
DIV_END
    RETURN

DELAY_M
    MOVLW d'3'
    MOVWF D1
DL1 MOVLW d'255'
    MOVWF D2
DL2 NOP
    DECFSZ D2, F
    GOTO DL2
    DECFSZ D1, F
    GOTO DL1
    RETURN

; --- UART GONDERME (Kesme Icinde Kullanilan) ---
UART_TX_ISR
    BSF STATUS, RP0     ; Bank 1'e gec (TXSTA icin)
WT_TX
    BTFSS TXSTA, TRMT   ; Buffer bos mu?
    GOTO WT_TX
    BCF STATUS, RP0     ; Bank 0'a don
    MOVWF TXREG         ; Veriyi gonder
    RETURN

; --- SENSOR SURUCULERI ---
READ_LDR
    MOVLW b'10000001'   ; Kanal 0
    MOVWF ADCON0
    CALL ADC_WAIT
    MOVWF LDR_VAL
    RETURN

READ_POT
    MOVLW b'10001001'   ; Kanal 1
    MOVWF ADCON0
    CALL ADC_WAIT
    MOVWF POT_VAL
    RETURN

ADC_WAIT
    MOVLW d'5'
    MOVWF D1
AD_L DECFSZ D1, F
    GOTO AD_L
    BSF ADCON0, GO
WT_AD
    BTFSC ADCON0, GO
    GOTO WT_AD
    MOVF ADRESH, W
    RETURN

; --- STEP MOTOR ---
STEP_CW
    INCF PHASE, F
    MOVF PHASE, W
    ANDLW 0x03
    CALL GET_PHASE
    MOVWF PORTD
    RETURN

STEP_CCW
    DECF PHASE, F
    MOVF PHASE, W
    ANDLW 0x03
    CALL GET_PHASE
    MOVWF PORTD
    RETURN

GET_PHASE
    ADDWF PCL, F
    RETLW b'00010000'
    RETLW b'00100000'
    RETLW b'01000000'
    RETLW b'10000000'

; --- LCD KUTUPHANESI ---
LCD_REFRESH
    ; Satir 1
    MOVLW 0x80
    CALL LCD_CMD
    MOVLW '+'
    CALL LCD_DAT
    MOVF TEMP_INT, W
    CALL WRITE_NUM_2
    MOVLW '.'
    CALL LCD_DAT
    MOVF TEMP_FRAC, W
    ADDLW '0'
    CALL LCD_DAT
    MOVLW 0xDF
    CALL LCD_DAT
    MOVLW 'C'
    CALL LCD_DAT
    MOVLW ' '
    CALL LCD_DAT
    MOVLW '1'
    CALL LCD_DAT
    MOVLW '0'
    CALL LCD_DAT
    MOVLW '1'
    CALL LCD_DAT
    MOVLW '3'
    CALL LCD_DAT
    MOVLW 'h'
    CALL LCD_DAT
    MOVLW 'P'
    CALL LCD_DAT
    MOVLW 'a'
    CALL LCD_DAT

    ; Satir 2
    MOVLW 0xC0
    CALL LCD_CMD
    MOVF LDR_VAL, W
    CALL WRITE_NUM_5
    MOVLW 'L'
    CALL LCD_DAT
    MOVLW 'u'
    CALL LCD_DAT
    MOVLW 'x'
    CALL LCD_DAT
    MOVLW ' '
    CALL LCD_DAT
    MOVF PERDE_YZD, W
    CALL WRITE_NUM_2
    MOVLW '.'
    CALL LCD_DAT
    MOVLW '0'
    CALL LCD_DAT
    MOVLW '%'
    CALL LCD_DAT
    RETURN

WRITE_NUM_5
    MOVWF SAYI_L
    MOVLW '0'
    CALL LCD_DAT
    MOVLW '0'
    CALL LCD_DAT
    CLRF YUZLER
C_100_5
    MOVLW d'100'
    SUBWF SAYI_L, W
    BTFSS STATUS, C
    GOTO P_100_5
    MOVWF SAYI_L
    INCF YUZLER, F
    GOTO C_100_5
P_100_5
    MOVF YUZLER, W
    ADDLW '0'
    CALL LCD_DAT
    CLRF ONLAR
C_10_5
    MOVLW d'10'
    SUBWF SAYI_L, W
    BTFSS STATUS, C
    GOTO P_10_5
    MOVWF SAYI_L
    INCF ONLAR, F
    GOTO C_10_5
P_10_5
    MOVF ONLAR, W
    ADDLW '0'
    CALL LCD_DAT
    MOVF SAYI_L, W
    ADDLW '0'
    CALL LCD_DAT
    RETURN

WRITE_NUM_2
    MOVWF SAYI_L
    CLRF ONLAR
    MOVLW d'100'
    SUBWF SAYI_L, W
    BTFSC STATUS, C
    MOVLW d'99'
    BTFSC STATUS, C
    MOVWF SAYI_L
C_10_2
    MOVLW d'10'
    SUBWF SAYI_L, W
    BTFSS STATUS, C
    GOTO C_1_2
    MOVWF SAYI_L
    INCF ONLAR, F
    GOTO C_10_2
C_1_2
    MOVF ONLAR, W
    ADDLW '0'
    CALL LCD_DAT
    MOVF SAYI_L, W
    ADDLW '0'
    CALL LCD_DAT
    RETURN

LCD_INIT
    CALL DELAY_LONG
    MOVLW 0x03
    CALL LCD_NIB
    CALL DELAY_SHORT
    MOVLW 0x03
    CALL LCD_NIB
    CALL DELAY_SHORT
    MOVLW 0x03
    CALL LCD_NIB
    CALL DELAY_SHORT
    MOVLW 0x02
    CALL LCD_NIB
    MOVLW 0x28
    CALL LCD_CMD
    MOVLW 0x0C
    CALL LCD_CMD
    MOVLW 0x06
    CALL LCD_CMD
    MOVLW 0x01
    CALL LCD_CMD
    CALL DELAY_LONG
    RETURN

LCD_NIB
    MOVWF LCD_VAR
    MOVF PORTB, W
    ANDLW 0xF0
    MOVWF TEMP_PORT
    MOVF LCD_VAR, W
    ANDLW 0x0F
    IORWF TEMP_PORT, F
    MOVF TEMP_PORT, W
    MOVWF PORTB
    BSF PORTB, 5
    NOP
    BCF PORTB, 5
    RETURN

LCD_CMD
    BCF PORTB, 4
    GOTO LCD_SEND
LCD_DAT
    BSF PORTB, 4
LCD_SEND
    MOVWF LCD_VAR
    SWAPF LCD_VAR, W
    ANDLW 0x0F
    MOVWF D1
    BTFSC PORTB, 4
    BSF D1, 4
    MOVF D1, W
    MOVWF PORTB
    BSF PORTB, 5
    NOP
    BCF PORTB, 5
    MOVF LCD_VAR, W
    ANDLW 0x0F
    MOVWF D1
    BTFSC PORTB, 4
    BSF D1, 4
    MOVF D1, W
    MOVWF PORTB
    BSF PORTB, 5
    NOP
    BCF PORTB, 5
    CALL DELAY_SHORT
    RETURN

DELAY_SHORT
    MOVLW d'50'
    MOVWF D1
DS_L DECFSZ D1, F
    GOTO DS_L
    RETURN

DELAY_LONG
    MOVLW d'100'
    MOVWF D1
DL_L MOVLW d'200'
    MOVWF D2
DL_L2 DECFSZ D2, F
    GOTO DL_L2
    DECFSZ D1, F
    GOTO DL_L
    RETURN

    END