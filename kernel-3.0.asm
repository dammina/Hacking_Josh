;*****************start of the kernel code***************
[org 0x000]
[bits 16]

[SEGMENT .text]

;START #####################################################
    mov ax, 0x0100			;location where kernel is loaded
    mov ds, ax
    mov es, ax
    
    cli
    mov ss, ax				;stack segment
    mov sp, 0xFFFF			;stack pointer at 64k limit
    sti

    push dx
    push es
    xor ax, ax
    mov es, ax
    cli
    mov word [es:0x21*4], _int0x21	; setup interrupt service
    mov [es:0x21*4+2], cs
    sti
    pop es
    pop dx

    mov si, WelcomeMessage   ; load message
    mov al, 0x01            ; request sub-service 0x01
    int 0x21

	call _shell				; call the shell
    
    int 0x19                ; reboot
;END #######################################################

_int0x21:
    _int0x21_ser0x01:       ;service 0x01
    cmp al, 0x01            ;see if service 0x01 wanted
    jne _int0x21_end        ;goto next check (now it is end)
    
    _int0x21_ser0x01_start:
    lodsb                   ; load next character
    or  al, al              ; test for NUL character
    jz  _int0x21_ser0x01_end
    mov ah, 0x0E            ; BIOS teletype
    mov bh, 0x00            ; display page 0
    mov bl, 0x07            ; text attribute
    int 0x10                ; invoke BIOS
    jmp _int0x21_ser0x01_start
    _int0x21_ser0x01_end:
    jmp _int0x21_end

    _int0x21_end:
    iret

_shell:
	_shell_begin:
	;move to next line
	call _display_endl

	;display prompt
	call _display_prompt

	;get user command
	call _get_command
	
	;split command into components
	call _split_cmd

	;check command & perform action

	; empty command
	_cmd_none:		
	mov si, strCmd0
	cmp BYTE [si], 0x00
	jne	_cmd_ver		;next command
	jmp _cmd_done
	
	; display version
	_cmd_ver:		
	mov si, strCmd0
	mov di, cmdVer
	mov cx, 4
	repe	cmpsb
	jne	NameCommand		;next command
	
	call _display_endl
	mov si, OSName		;display version
	mov al, 0x01
    int 0x21
	call _display_space
	mov si, txtVersion		;display version
	mov al, 0x01
    int 0x21
	call _display_space

	mov si, MajorVersion		
	mov al, 0x01
    int 0x21
	mov si, MinorVersion
	mov al, 0x01
    int 0x21
	jmp _cmd_done

	;display name
	NameCommand:
	mov si, strCmd0
	mov di, cmdName
	mov cx, 5
	repe	cmpsb
	jne	HardwareCommand		;next command

	call _display_endl
	mov si, MyName
	mov al, 0x01
	
	int 0x21
	jmp _cmd_done


	;display hardware info
	HardwareCommand:
	mov si, strCmd0
	mov di,cmdHardware
	mov cx,2
	repe cmpsb
	jne	_cmd_exit
	call HardwareInformation
	jmp _cmd_done


	; exit shell
	_cmd_exit:		
	mov si, strCmd0
	mov di, cmdExit
	mov cx, 5
	repe	cmpsb
	jne	_cmd_unknown		;next command

	je _shell_end			;exit from shell

	_cmd_unknown:
	call _display_endl
	mov si, msgUnknownCmd		;unknown command
	mov al, 0x01
    int 0x21

	_cmd_done:

	;call _display_endl
	jmp _shell_begin
	
	_shell_end:
	ret

PrintMethod:
	mov al, 0x01
	int 0x21
ret

HardwareInformation:
	call _display_endl
	call _display_endl
	mov si,SystemHardware
	call PrintMethod
	call _display_endl
	mov si,EndOfLine
	call PrintMethod
	call _display_endl
;Processor
	mov si,ProcessorInfo
	call PrintMethod
	
	mov si,TAB
	call PrintMethod

	mov eax,0
	cpuid
	mov [CPUvendor],ebx
	mov [CPUvendor+4],edx
	mov [CPUvendor+8],ecx
	
	mov si,CPUvendor
	call PrintMethod
	call _display_endl
	
	mov eax,80000002h
	cpuid
	mov [ProcessorType],eax
	mov [ProcessorType+4],ebx
	mov [ProcessorType+8],edx
	mov [ProcessorType+12],ecx
	mov si,ProcessorType
	call PrintMethod

	
	mov eax,80000003h
	cpuid
	mov [ProcessorType2],eax
	mov [ProcessorType2+4],ebx
	mov [ProcessorType2+8],edx
	mov [ProcessorType2+12],ecx
	mov si,ProcessorType2
	call PrintMethod

	mov eax,80000004h
	cpuid
	mov [ProcessorType3],eax
	mov [ProcessorType3+4],ebx
	mov [ProcessorType3+8],edx
	mov [ProcessorType3+12],ecx
	mov si,ProcessorType3
	call PrintMethod

	call _display_endl	
	mov si,EndOfLine
	call PrintMethod

;Ram
	call _display_endl
	
	mov si,RAMinfo
	call PrintMethod
	
	mov si,TAB
	call PrintMethod

	mov ax,0xE801
	int 0x15		; get ram size into registers

	call _display_endl

	mov si,RAMsize
	call PrintMethod
	
	call _print_reg
	
	call _display_endl

	mov si,EndOfLine
	call PrintMethod

;Date and Time
	call _display_endl
	call _time_string
	
	mov si,SystemTime
	call PrintMethod
	
	mov si,TAB
	call PrintMethod

	mov si, BX
	call PrintMethod
	

ret


_time_string:
	pusha				;save all the registers

	mov di, bx			; Location to place time string

	clc				; For buggy BIOSes
	mov ah, 2			; Get time data from BIOS in BCD format
	int 1Ah
	jnc .read

	clc
	mov ah, 2			; BIOS was updating (~1 in 500 chance), so try again
	int 1Ah

.read:
	mov al, ch			; Convert hours to integer for AM/PM test
	call _bcd_to_dec
	mov dx, ax			; Save

	mov al,	ch			; Hour
	shr al, 4			; Tens digit - move higher BCD number into lower bits
	and ch, 0Fh			; Ones digit
	test byte [fmt_12_24], 0FFh
	jz .twelve_hr

	call .add_digit			; BCD already in 24-hour format
	mov al, ch
	call .add_digit
	jmp short .minutes

.twelve_hr:
	cmp dx, 0			; If 00mm, make 12 AM
	je .midnight

	cmp dx, 10			; Before 1000, OK to store 1 digit
	jl .twelve_st1

	cmp dx, 12			; Between 1000 and 1300, OK to store 2 digits
	jle .twelve_st2

	mov ax, dx			; Change from 24 to 12-hour format
	sub ax, 12
	mov bl, 10
	div bl
	mov ch, ah

	cmp al, 0			; 1-9 PM
	je .twelve_st1

	jmp short .twelve_st2		; 10-11 PM

.midnight:
	mov al, 1
	mov ch, 2

.twelve_st2:
	call .add_digit			; Modified BCD, 2-digit hour
.twelve_st1:
	mov al, ch
	call .add_digit

	mov al, ':'			; Time separator (12-hr format)
	stosb

.minutes:
	mov al, cl			; Minute
	shr al, 4			; Tens digit - move higher BCD number into lower bits
	and cl, 0Fh			; Ones digit
	call .add_digit
	mov al, cl
	call .add_digit

	mov al, ' '			; Separate time designation
	stosb

	mov si, .hours_string		; Assume 24-hr format
	test byte [fmt_12_24], 0FFh
	jnz .copy

	mov si, .pm_string		; Assume PM
	cmp dx, 12			; Test for AM/PM
	jg .copy

	mov si, .am_string		; Was actually AM

.copy:
	lodsb				; Copy designation, including terminator
	stosb
	cmp al, 0
	jne .copy

	popa
	ret


.add_digit:
	add al, '0'			; Convert to ASCII
	stosb				; Put into string buffer
	ret


	.hours_string	db 'hours', 0
	.am_string 	db 'AM', 0
	.pm_string 	db 'PM', 0

_bcd_to_dec:
	pusha

	mov bl, al			; Store entire number for now

	and ax, 0Fh			; Zero-out high bits
	mov cx, ax			; CH/CL = lower BCD number, zero extended

	shr bl, 4			; Move higher BCD number into lower bits, zero fill msb
	mov al, 10
	mul bl				; AX = 10 * BL

	add ax, cx			; Add lower BCD to 10*higher
	mov [.tmp], ax

	popa
	mov ax, [.tmp]			; And return it in AX!
	ret


	.tmp	dw 0





_print_reg:


	_hex2dec:

	push ax                  ; save  AX
	push bx                  ; save  CX
	push cx                  ; save  DX
	push si                  ; save  SI
	mov ax,dx                ; copy number into AX
	mov si,10                ; SI will be our divisor
	xor cx,cx                ; clean up the CX

	_non_zero:

	xor dx,dx                ; clean up the DX
	div si                   ; divide by 10
	push dx                  ; push number onto the stack
	inc cx                   ; increment CX to do it more times
	or ax,ax                 ; end of the number?
	jne _non_zero             ; no? Keep chuggin' away

	_write_digits:
	pop dx                   ; get the digit off DX
	add dl,48                ; add 48 to get ASCII
	mov al, dl
	mov ah, 0x0e
	int 0x10
	loop _write_digits

	pop si                   ; restore  SI
	pop cx                   ; restore  DX
	pop bx                   ; restore  CX
	pop ax                   ; restore  AX
ret                      ; End of procedure!

_get_command:
	;initiate count
	mov BYTE [cmdChrCnt], 0x00
	mov di, strUserCmd

	_get_cmd_start:
	mov ah, 0x10		;get character
	int 0x16

	cmp al, 0x00		;check if extended key
	je _extended_key
	cmp al, 0xE0		;check if new extended key
	je _extended_key

	cmp al, 0x08		;check if backspace pressed
	je _backspace_key

	cmp al, 0x0D		;check if Enter pressed
	je _enter_key

	mov bh, [cmdMaxLen]		;check if maxlen reached
	mov bl, [cmdChrCnt]
	cmp bh, bl
	je	_get_cmd_start

	;add char to buffer, display it and start again
	mov [di], al			;add char to buffer
	inc di					;increment buffer pointer
	inc BYTE [cmdChrCnt]	;inc count

	mov ah, 0x0E			;display character
	mov bl, 0x07
	int 0x10
	jmp	_get_cmd_start

	_extended_key:			;extended key - do nothing now
	jmp _get_cmd_start

	_backspace_key:
	mov bh, 0x00			;check if count = 0
	mov bl, [cmdChrCnt]
	cmp bh, bl
	je	_get_cmd_start		;yes, do nothing
	
	dec BYTE [cmdChrCnt]	;dec count
	dec di

	;check if beginning of line
	mov	ah, 0x03		;read cursor position
	mov bh, 0x00
	int 0x10

	cmp dl, 0x00
	jne	_move_back
	dec dh
	mov dl, 79
	mov ah, 0x02
	int 0x10

	mov ah, 0x09		; display without moving cursor
	mov al, ' '
    mov bh, 0x00
    mov bl, 0x07
	mov cx, 1			; times to display
    int 0x10
	jmp _get_cmd_start

	_move_back:
	mov ah, 0x0E		; BIOS teletype acts on backspace!
    mov bh, 0x00
    mov bl, 0x07
    int 0x10
	mov ah, 0x09		; display without moving cursor
	mov al, ' '
    mov bh, 0x00
    mov bl, 0x07
	mov cx, 1			; times to display
    int 0x10
	jmp _get_cmd_start

	_enter_key:
	mov BYTE [di], 0x00
	ret

_split_cmd:
	;adjust si/di
	mov si, strUserCmd
	;mov di, strCmd0

	;move blanks
	_split_mb0_start:
	cmp BYTE [si], 0x20
	je _split_mb0_nb
	jmp _split_mb0_end

	_split_mb0_nb:
	inc si
	jmp _split_mb0_start

	_split_mb0_end:
	mov di, strCmd0

	_split_1_start:			;get first string
	cmp BYTE [si], 0x20
	je _split_1_end
	cmp BYTE [si], 0x00
	je _split_1_end
	mov al, [si]
	mov [di], al
	inc si
	inc di
	jmp _split_1_start

	_split_1_end:
	mov BYTE [di], 0x00

	;move blanks
	_split_mb1_start:
	cmp BYTE [si], 0x20
	je _split_mb1_nb
	jmp _split_mb1_end

	_split_mb1_nb:
	inc si
	jmp _split_mb1_start

	_split_mb1_end:
	mov di, strCmd1

	_split_2_start:			;get second string
	cmp BYTE [si], 0x20
	je _split_2_end
	cmp BYTE [si], 0x00
	je _split_2_end
	mov al, [si]
	mov [di], al
	inc si
	inc di
	jmp _split_2_start

	_split_2_end:
	mov BYTE [di], 0x00

	;move blanks
	_split_mb2_start:
	cmp BYTE [si], 0x20
	je _split_mb2_nb
	jmp _split_mb2_end

	_split_mb2_nb:
	inc si
	jmp _split_mb2_start

	_split_mb2_end:
	mov di, strCmd2

	_split_3_start:			;get third string
	cmp BYTE [si], 0x20
	je _split_3_end
	cmp BYTE [si], 0x00
	je _split_3_end
	mov al, [si]
	mov [di], al
	inc si
	inc di
	jmp _split_3_start

	_split_3_end:
	mov BYTE [di], 0x00

	;move blanks
	_split_mb3_start:
	cmp BYTE [si], 0x20
	je _split_mb3_nb
	jmp _split_mb3_end

	_split_mb3_nb:
	inc si
	jmp _split_mb3_start

	_split_mb3_end:
	mov di, strCmd3

	_split_4_start:			;get fourth string
	cmp BYTE [si], 0x20
	je _split_4_end
	cmp BYTE [si], 0x00
	je _split_4_end
	mov al, [si]
	mov [di], al
	inc si
	inc di
	jmp _split_4_start

	_split_4_end:
	mov BYTE [di], 0x00

	;move blanks
	_split_mb4_start:
	cmp BYTE [si], 0x20
	je _split_mb4_nb
	jmp _split_mb4_end

	_split_mb4_nb:
	inc si
	jmp _split_mb4_start

	_split_mb4_end:
	mov di, strCmd4

	_split_5_start:			;get last string
	cmp BYTE [si], 0x20
	je _split_5_end
	cmp BYTE [si], 0x00
	je _split_5_end
	mov al, [si]
	mov [di], al
	inc si
	inc di
	jmp _split_5_start

	_split_5_end:
	mov BYTE [di], 0x00

	ret

_display_space:
	mov ah, 0x0E                            ; BIOS teletype

	mov al, 0x20
    mov bh, 0x00                            ; display page 0
    mov bl, 0x07                            ; text attribute
    int 0x10                                ; invoke BIOS
	ret

_display_endl:
	mov ah, 0x0E		; BIOS teletype acts on newline!
    mov al, 0x0D
	mov bh, 0x00
    mov bl, 0x07
    int 0x10
	mov ah, 0x0E		; BIOS teletype acts on linefeed!
    mov al, 0x0A
	mov bh, 0x00
    mov bl, 0x07
    int 0x10
	ret

_display_prompt:
	mov si, Prompt
	mov al, 0x01
	int 0x21
	ret

[SEGMENT .data]
    WelcomeMessage   db  "Welcome to JOSH V1.0 OS Edited by Dammina", 0x00
	Prompt		db	"100466H $ ", 0x00
	cmdMaxLen		db	255			;maximum length of commands

	OSName		db	"JOSH", 0x00	;OS details
	MajorVersion		db	"1", 0x00
	MinorVersion		db	".00", 0x00
	MyName			db	"Dammina Sahabandu",0x00
	
	TAB		db	"	",0x00
	EndOfLine	db	"____________________________________________",0x00
	SystemHardware	db	"System Hardware Info:",0x00
	ProcessorInfo	db	"Processor Info:",0x00
	RAMinfo		db	"Ram Info:",0x00
	RAMsize	db	"RAM Size (*64KB) :",0x00
	CPUvendor	db	"111111111111",0x00
	ProcessorType	db	"$$$$$$$$$$$$$$$$",0x00
	ProcessorType2	db	"$$$$$$$$$$$$$$$$",0x00
	ProcessorType3	db	"$$$$$$$$$$$$$$$$",0x00
	SystemTime		        db "Sys. Time - ",0x00
	space 		db ", Time -",0x00
        fmt_12_24	db 0		; Non-zero = 24-hr format
	fmt_date	db 0, '/'	; 0, 1, 2 = M/D/Y, D/M/Y or Y/M/D
					; Bit 7 = use name for months
					; If bit 7 = 0, second byte = separator character


	cmdVer			db	"ver", 0x00		; internal commands
	cmdExit			db	"ext", 0x00
	cmdName			db	"name", 0x00
	cmdHardware		db	"hw",0x00

	txtVersion		db	"version", 0x00	;messages and other strings
	msgUnknownCmd	db	"Unknown command or bad file name!", 0x00

[SEGMENT .bss]
	strUserCmd	resb	256		;buffer for user commands
	cmdChrCnt	resb	1		;count of characters
	strCmd0		resb	256		;buffers for the command components
	strCmd1		resb	256
	strCmd2		resb	256
	strCmd3		resb	256
	strCmd4		resb	256

;********************end of the kernel code********************
