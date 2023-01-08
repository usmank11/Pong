# Pong
Pong game written in SystemVerilog

To simulate, you will need Verilator and SDL. To install on mac, run:
```
brew install verilator sdl2
```

To build, open a terminal in project directory and run:
```
verilator -I../ -cc pong.sv --exe main.cpp -o pong \
    -CFLAGS "$(sdl2-config --cflags)" -LDFLAGS "$(sdl2-config --libs)"

make -C ./obj_dir -f Vpong.mk
```

To run the simulation:
```
./obj_dir/pong
```
