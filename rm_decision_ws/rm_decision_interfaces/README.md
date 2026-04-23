# Mock referee and vision: publish test messages

- robot_status
- game_status
  ```zsh
  source install/setup.zsh
    ros2 topic pub -r 1 /game_status rm_decision_interfaces/msg/GameStatus "{
        game_progress: 3,
        stage_remain_time: 5,
    }"
  ```
- all_robot_hp
- friend_location
    `hero`: ally sentry spawn  
    `engineer`: rune / energy mechanism (allied side)  
    `standard_3`: allied elevated ring  
    `standard_4`: enemy outpost  
    `standard_5`: enemy base  
- RFID

