package main

import "core:c/libc"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

BOARD_WIDTH :: 64
BOARD_HEIGHT :: 32

Cell :: struct {
	x, y:     int,
	is_alive: bool,
}

Board :: [BOARD_HEIGHT][BOARD_WIDTH]Cell

main :: proc() {
	if len(os.args) < 2 {
		fmt.print("Usage: %s <filename>\n", os.args[0])
		os.exit(1)
	}

	board: Board
	init_board_from_file(os.args[1], &board)
	run(&board)
}

init_board_from_file :: proc(filename: string, cells: ^Board) {
	data, ok := os.read_entire_file_from_filename(filename)
	if !ok {
		fmt.print("Failed to read file: %s\n", filename)
		os.exit(1)
	}

	defer delete(data)

	iter := string(data)
	lines := strings.split_lines(iter, context.allocator)
	defer delete(lines)

	for line, y in lines {
		assert(y <= BOARD_HEIGHT, "y index out of bounds")
		for c, x in line {
			assert(x <= BOARD_WIDTH, "x index out of bounds")
			if c == '#' {
				cells[y][x].is_alive = true
			}
		}
	}
}

run :: proc(board: ^Board) {
	// create neighbour buffer
	neighbour_buffer: [BOARD_HEIGHT][BOARD_WIDTH]int

	neighbour_barrier := sync.Barrier{}
	sync.barrier_init(&neighbour_barrier, BOARD_HEIGHT * BOARD_WIDTH)

	update_barrier := sync.Barrier{}
	// +1 for to wait for the main thread to finish drawing the board
	// before continuing to the next generation.
	sync.barrier_init(&update_barrier, BOARD_HEIGHT * BOARD_WIDTH + 1)

	Data :: struct {
		x, y:             int,
		neighbour_buffer: ^[BOARD_HEIGHT][BOARD_WIDTH]int,
		board:            ^Board,
		count_barrier:    ^sync.Barrier,
		update_barrier:   ^sync.Barrier,
	}

	// start all worker threads, one per cell
	for y in 0 ..< len(board) {
		for x in 0 ..< len(board[y]) {
			data := Data{x, y, &neighbour_buffer, board, &neighbour_barrier, &update_barrier}
			th := thread.create_and_start_with_poly_data(data, worker_proc)
		}
	}

	for generation in 0 ..< 1000 {
		number_of_alive_cells := 0
		// Draw the board
		libc.system("clear")
		for y in 0 ..< len(board) {
			for x in 0 ..< len(board[y]) {
				if board[y][x].is_alive {
					number_of_alive_cells += 1
					fmt.print("#")
				} else {
					fmt.print(".")
				}
			}

			fmt.print("\n")
		}

		fmt.printf("Generation: %d, Alive cells: %d\n", generation, number_of_alive_cells)

		time.sleep(75 * time.Millisecond)

		// Wait for all workers to finish updating the board
		sync.barrier_wait(&update_barrier)
	}

	worker_proc :: proc(data: Data) {
		x := data.x
		y := data.y

		for {
			sync.barrier_wait(data.update_barrier)

			// NOTE: Need to calculate number of neighbours before updating the 
			// board since the order in which updates occur would affect the result.
			// thereof the barrier
			data.neighbour_buffer[y][x] = number_of_alive_neighbours(data.board, x, y)
			sync.barrier_wait(data.count_barrier)

			neighbours := data.neighbour_buffer[y][x]
			// RULES
			// 1. If a cell is alive and has fewer than 2 or 4 or more
			//   neighbours, it dies.
			// 2. If a cell is dead and has exactly 3 neighbours, it becomes alive.
			// 3. Otherwise, the cell stays the same.
			if neighbours < 2 || neighbours > 3 {
				data.board[y][x].is_alive = false
			} else if neighbours == 3 {
				data.board[y][x].is_alive = true
			}
		}
	}
}

number_of_alive_neighbours :: proc(board: ^Board, x, y: int) -> int {
	neighbours := 0
	for dy := -1; dy <= 1; dy += 1 {
		for dx := -1; dx <= 1; dx += 1 {
			if dx == 0 && dy == 0 {
				continue
			}

			xx := x + dx
			yy := y + dy

			// skip out of bounds cells
			if xx < 0 || xx >= BOARD_WIDTH || yy < 0 || yy >= BOARD_HEIGHT {
				continue
			}

			if board[yy][xx].is_alive {
				neighbours += 1
			}
		}
	}

	return neighbours
}
