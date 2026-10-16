import pygame
import random
import sys

# 初始化 pygame
pygame.init()

# 常量设置
WIDTH, HEIGHT = 600, 400
CELL_SIZE = 20
GRID_WIDTH = WIDTH // CELL_SIZE
GRID_HEIGHT = HEIGHT // CELL_SIZE

# 颜色定义
BLACK = (0, 0, 0)
WHITE = (255, 255, 255)
GREEN = (0, 255, 0)
RED = (255, 0, 0)
GRAY = (40, 40, 40)

# 设置显示窗口
screen = pygame.display.set_mode((WIDTH, HEIGHT))
pygame.display.set_caption("贪吃蛇")
clock = pygame.time.Clock()
font = pygame.font.SysFont(None, 36)

# 方向映射
UP = (0, -1)
DOWN = (0, 1)
LEFT = (-1, 0)
RIGHT = (1, 0)


class Snake:
    def __init__(self):
        self.length = 1
        self.positions = [(GRID_WIDTH // 2, GRID_HEIGHT // 2)]
        self.direction = random.choice([UP, DOWN, LEFT, RIGHT])
        self.color = GREEN
        self.score = 0

    def get_head_position(self):
        return self.positions[0]

    def update(self):
        cur = self.get_head_position()
        x, y = self.direction
        new = (
            (cur[0] + x) % GRID_WIDTH,
            (cur[1] + y) % GRID_HEIGHT
        )
        # 撞到自己则游戏结束
        if new in self.positions[1:]:
            return False
        self.positions.insert(0, new)
        if len(self.positions) > self.length:
            self.positions.pop()
        return True

    def reset(self):
        self.length = 1
        self.positions = [(GRID_WIDTH // 2, GRID_HEIGHT // 2)]
        self.direction = random.choice([UP, DOWN, LEFT, RIGHT])
        self.score = 0

    def render(self, surface):
        for p in self.positions:
            rect = pygame.Rect((p[0] * CELL_SIZE, p[1] * CELL_SIZE), (CELL_SIZE, CELL_SIZE))
            pygame.draw.rect(surface, self.color, rect)
            pygame.draw.rect(surface, GRAY, rect, 1)


class Food:
    def __init__(self):
        self.position = (0, 0)
        self.color = RED
        self.randomize_position()

    def randomize_position(self):
        self.position = (
            random.randint(0, GRID_WIDTH - 1),
            random.randint(0, GRID_HEIGHT - 1)
        )

    def render(self, surface):
        rect = pygame.Rect((self.position[0] * CELL_SIZE, self.position[1] * CELL_SIZE), (CELL_SIZE, CELL_SIZE))
        pygame.draw.rect(surface, self.color, rect)
        pygame.draw.rect(surface, GRAY, rect, 1)


def draw_grid(surface):
    for x in range(0, WIDTH, CELL_SIZE):
        pygame.draw.line(surface, GRAY, (x, 0), (x, HEIGHT))
    for y in range(0, HEIGHT, CELL_SIZE):
        pygame.draw.line(surface, GRAY, (0, y), (WIDTH, y))


def main():
    snake = Snake()
    food = Food()

    while True:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                pygame.quit()
                sys.exit()
            elif event.type == pygame.KEYDOWN:
                if event.key == pygame.K_UP and snake.direction != DOWN:
                    snake.direction = UP
                elif event.key == pygame.K_DOWN and snake.direction != UP:
                    snake.direction = DOWN
                elif event.key == pygame.K_LEFT and snake.direction != RIGHT:
                    snake.direction = LEFT
                elif event.key == pygame.K_RIGHT and snake.direction != LEFT:
                    snake.direction = RIGHT
                elif event.key == pygame.K_SPACE:
                    # 空格键重新开始
                    snake.reset()
                    food.randomize_position()

        # 更新蛇的位置
        if not snake.update():
            # 撞到自己，游戏结束
            snake.reset()
            food.randomize_position()

        # 检查是否吃到食物
        if snake.get_head_position() == food.position:
            snake.length += 1
            snake.score += 1
            food.randomize_position()

        # 绘制
        screen.fill(BLACK)
        draw_grid(screen)
        snake.render(screen)
        food.render(screen)

        # 显示得分
        score_text = font.render(f"得分: {snake.score}", True, WHITE)
        screen.blit(score_text, (10, 10))

        pygame.display.update()
        clock.tick(10)  # 控制帧率：10 FPS，适合贪吃蛇节奏


if __name__ == "__main__":
    main()