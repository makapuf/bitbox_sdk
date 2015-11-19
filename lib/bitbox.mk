# BITBOX environment variable should point to the base bitbox source  dir (where this file is)

# DEFINE in outside makefile
#   NAME : name of the project
#   GAME_C_FILES c files of the project
#	GAME_BINARY_FILES : binary files to embed as part of the main binary ROM
#   GAME_C_OPTS : C language options. Those will be used for the ARM game as well as the emulator.
#		- define with whatever defines are needed with -DXYZ CFLAGS .
#		  they can be used to define specific kernel resolution. 
#   	  In particular, define one of VGAMODE_640, VGAMODE_800, VGAMODE_320 or VGA_640_OVERCLOCK
#   	  to set up a resolution in the kernel (those will be used in kconf.h)
#
#       - Other specific flags : 
#             NO_USB,       - when you don't want to use USB input related function)
#             USE_SDCARD,   - when you want to use or compile SDcard or fatfs related functions in the game 
#             USE_ENGINE,   - when you want to use the engine
#             USE_SD_SENSE  - enabling this will disable being used on rev2 !
#			  DISABLE_ESC_EXIT - for the emulator only, disable quit when pressing ESC
#             KEYB_FR       - enable AZERTY keybard mapping
#			  PROFILE		- enable profiling (red line / pixels onscreen)

#   Simple mode related : 
#        VGA_SIMPLE_MODE=0 .. 12 (see simple.h for modes)
#   Simple Sampler : 
#        USE_SAMPLER=1

CC = arm-none-eabi-gcc
LD = arm-none-eabi-gcc
OBJCOPY = arm-none-eabi-objcopy

DEFINES += -DARM_MATH_CM4  -DAUDIO 

# USB defines
ifdef NO_USB
DEFINES += -DNO_USB
else
DEFINES += -DUSE_USB_OTG_HS -DUSE_EMBEDDED_PHY -DUSE_USB_OTG_FS
endif

DEFINES += -DUSE_STDPERIPH_DRIVER 

MCU = -mthumb -mcpu=cortex-m4 -mfloat-abi=hard -mfpu=fpv4-sp-d16 -march=armv7e-m 
C_OPTS = -std=c99 \
	$(MCU) \
	-D__FPU_USED=1 \
	-mlittle-endian \
	-I$(BITBOX)/lib/ \
	-I$(BITBOX)/lib/CMSIS/Include \
	-I$(BITBOX)/lib/StdPeriph \
	-O3 -g \
	-Wall \
	-ffast-math \
	-fsingle-precision-constant \
	-ffunction-sections -fdata-sections \
	-funroll-loops \
	-fomit-frame-pointer 
	#-funroll-all-loops \
	#-Werror \

LD_FLAGS = $(MCU) -nostartfiles
LIBS =	-lm -lc

SOURCE_DIR =.

BUILD_DIR =build
LIB_SOURCE_DIR =$(BITBOX)/lib
LIB_STD_SOURCE_DIR =$(BITBOX)/lib/StdPeriph

# replace with linker_raw if you want to overwrite bootloader
LINKER_SCRIPT = $(BITBOX)/lib/Linker_loader.ld
FLASH_START = 0x08004000
#LINKER_SCRIPT = lib/Linker_raw.ld
#FLASH_START = 0x08000000

KERNEL_FILES += startup.c system.c board.c \
	new_vga.c bitbox_main.c audio.c \
	stm32f4xx_gpio.c \
	stm32f4xx_rcc.c \
	stm32f4xx_tim.c \
	misc.c 

ifndef NO_USB
	KERNEL_FILES += usb_bsp.c \
	usb_core.c \
	usb_hcd.c \
	usb_hcd_int.c \
	usbh_core.c \
	usbh_hcs.c \
	usbh_hid_core.c \
	usbh_hid_keybd.c \
	usbh_hid_mouse.c \
	usbh_hid_gamepad.c \
	usbh_hid_parse.c \
	usbh_ioreq.c \
	usbh_stdreq.c \
	stm32fxxx_it.c 
endif 

# fatfs related files
ifdef USE_SDCARD
KERNEL_FILES += fatfs/stm32f4_lowlevel.c fatfs/stm32f4_discovery_sdio_sd.c fatfs/ff.c fatfs/diskio.c
KERNEL_FILES += stm32f4xx_sdio.c stm32f4xx_dma.c 
endif 

# Engines related - engines are libs that stay on top of the kernel
# so they are included in the emulator. Most are optional

# - events
ENGINE_FILES += evt_queue.c
# - tiles & sprites
ifdef USE_ENGINE
ENGINE_FILES +=  blitter.c blitter_btc.c blitter_sprites.c blitter_tmap.c
endif

# - simple modes
ifdef VGA_SIMPLE_MODE
GAME_C_OPTS += -DVGA_SIMPLE_MODE=$(VGA_SIMPLE_MODE)
ENGINE_FILES +=  simple.c fonts.c
# those modes require kernel mode 800x600
ifneq ($(filter $(VGA_SIMPLE_MODE),1 2),)
GAME_C_OPTS += -DVGAMODE_800
endif 

# 800x600 O/C 192 to achieve this mode
ifneq ($(filter $(VGA_SIMPLE_MODE),11 ),)
GAME_C_OPTS += -DVGAMODE_800_OVERCLOCK
endif 

# 400x300 mode
ifeq ($(VGA_SIMPLE_MODE),4)
GAME_C_OPTS += -DVGAMODE_400
endif
# 320x240 mode
ifeq ($(VGA_SIMPLE_MODE),5)
GAME_C_OPTS += -DVGAMODE_320
endif

endif 

# - simple sampler
ifdef USE_SAMPLER
ENGINE_FILES += sampler.c
endif

# - chiptune engine
ifdef USE_CHIPTUNE 
$(warning the chiptune engine is about to change. Please change to the chiptune.h file)
ENGINE_FILES += chiptune_engine.c chiptune_player.c
endif


C_FILES = $(LIB_FILES) $(GAME_C_FILES) $(KERNEL_FILES) $(ENGINE_FILES)
S_FILES = memcpy-armv7m.S

OBJS = $(C_FILES:%.c=$(BUILD_DIR)/%.o) $(S_FILES:%.S=$(BUILD_DIR)/%.o) $(GAME_BINARY_FILES:%=$(BUILD_DIR)/%.o)

ALL_CFLAGS = $(C_OPTS) $(DEFINES) $(CFLAGS) $(GAME_C_OPTS)
ALL_LDFLAGS = $(LD_FLAGS) -Wl,-T,$(LINKER_SCRIPT),--gc-sections

AUTODEPENDENCY_CFLAGS=-MMD -MF$(@:.o=.d) -MT$@

all: $(NAME).bin $(NAME) $(EXTRA_FILES)

upload: $(NAME).bin
	openocd -f interface/stlink-v2.cfg -f target/stm32f4x_stlink.cfg \
	-c init -c "reset halt" -c "stm32f2x mass_erase 0" \
	-c "flash write_bank 0 $(NAME).bin 0" \
	-c "reset run" -c shutdown

debug: $(NAME).elf
	arm-none-eabi-gdb $(NAME).elf \
	--eval-command="target extended-remote :4242"

stlink: $(NAME).bin
	#arm-eabi-gdb $(NAME).elf --eval-command="target ext :4242"
	st-flash write $(NAME).bin $(FLASH_START)

# using dfu util	
dfu: $(NAME).bin
	dfu-util -D $< --dfuse-address 0x8000000 -a 0

# double colon to allow extra cleaning
clean::
	rm -rf $(BUILD_DIR) $(NAME).elf $(NAME).bin $(NAME) $(NAME)_test

$(NAME).bin: $(NAME).elf
	$(OBJCOPY) -O binary $^ $@
	chmod -x $@

$(NAME).elf: $(OBJS)
	$(LD) $(ALL_LDFLAGS) -o $@ $^ $(LIBS)
	chmod -x $@

.SUFFIXES: .o .c .S

$(BUILD_DIR)/%.o: $(LIB_SOURCE_DIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(ALL_CFLAGS) $(AUTODEPENDENCY_CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: $(LIB_SOURCE_DIR)/%.S
	@mkdir -p $(dir $@)
	$(CC) $(ALL_CFLAGS) $(AUTODEPENDENCY_CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: $(LIB_STD_SOURCE_DIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(ALL_CFLAGS) $(AUTODEPENDENCY_CFLAGS) -c $< -o $@

# ---------- data embedding 
$(BUILD_DIR)/binaries.h: 
	# should transform it using make syntax.
	@mkdir -p $(dir $@)
	echo "// AUTO GENERATED BY bitbox.mk DO NOT MODIFY " > $@
	echo "// -- binaries " > $@
	echo $(GAME_BINARY_FILES) | sed s/[/\.]/_/g | sed "s/ /\n/g" | sed "s/.*/extern const unsigned char \0[];/" >> $@ 
	echo "// -- lengths " >> $@
	echo $(GAME_BINARY_FILES) | sed s/[/\.]/_/g | sed "s/ /\n/g" | sed "s/.*/extern const unsigned int \0_len;/">> $@ 

$(BUILD_DIR)/%.c: % 
	@mkdir -p $(dir $@)
	$(info * embedding $< as $@)
	xxd -i $< | sed "s/unsigned/const unsigned/" > $@

$(BUILD_DIR)/%.o: $(BUILD_DIR)/%.c
	$(CC) $(ALL_CFLAGS) $(AUTODEPENDENCY_CFLAGS) -c $< -o $@

# ---------------------------------


$(BUILD_DIR)/%.o: $(SOURCE_DIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(ALL_CFLAGS) $(AUTODEPENDENCY_CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: $(SOURCE_DIR)/%.cpp
	@mkdir -p $(dir $@)
	$(CC) -fno-exceptions -fno-rtti -Wno-multichar $(subst -std=c99,-std=c++11,$(ALL_CFLAGS)) $(AUTODEPENDENCY_CFLAGS) -c $< -o $@


$(BUILD_DIR)/%.o: $(SOURCE_DIR)/%.S
	@mkdir -p $(dir $@)
	$(CC) $(ALL_CFLAGS) $(AUTODEPENDENCY_CFLAGS) -c $< -o $@

-include $(OBJS:.o=.d)
#--- Emulator

HOST = $(shell uname)
ifeq ($(HOST), Haiku)
  HOSTLIBS =
else
  HOSTLIBS = -lm
endif


$(NAME): $(GAME_C_FILES) $(GAME_CPP_FILES) $(BITBOX)/lib/emulator.c  $(GAME_BINARY_FILES:%=$(BUILD_DIR)/%.c) $(addprefix $(BITBOX)/lib/, $(ENGINE_FILES))
	gcc -Og -DEMULATOR  $(GAME_C_OPTS) $^ -I$(BITBOX)/lib/ -g -Wall -std=c99 $(HOSTLIBS) `sdl-config --cflags --libs` -lstdc++ -o $(NAME)

$(NAME)_test: $(GAME_C_FILES) $(GAME_CPP_FILES) $(BITBOX)/lib/tester.c  $(GAME_BINARY_FILES:%=$(BUILD_DIR)/%.c) $(addprefix $(BITBOX)/lib/, $(ENGINE_FILES))
	gcc -Og -DEMULATOR  $(GAME_C_OPTS) $^ -I$(BITBOX)/lib/ -g -Wall -std=c99 $(HOSTLIBS) -lstdc++ -o $(NAME)_test

test: $(NAME)_test
	./$(NAME)_test
