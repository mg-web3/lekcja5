# Programowanie Web3 - Fundamenty Blockchain i Solidity

Lekcja 5 kursu Programowanie Web3 - Fundamenty Blockchain i Solidity.

Kryptografia w blockchain.

![Kryptografia](5-cryptography.png)

## Instalacja i konfiguracja

1. Stwórz folder dla projektu i przejdź do niego: `mkdir nazwa-projektu` i `cd nazwa-projektu`
2. Stwórz nowy projekt Foundry: `forge init`
3. Zainstaluj biblioteki od OpenZeppelin i FoundryRandom: `forge install Openzeppelin/openzeppelin-contracts@v4.9.3`
4. Do pliku `foundry.toml` dodaj linijkę, która pozwoli kompilatorowi na poprawne mapowanie zależności: `remappings = ["@openzeppelin/=lib/openzeppelin-contracts/"]`
5. Zmień nazwę pliku : `mv src/Counter.sol src/KryptoGra.sol` i `mv test/Counter.t.sol test/KryptoGra.t.sol` kolejno `mv script/Counter.s.sol script/KryptoGra.s.sol`
6. Uzupełnij pliki źródłowe odpowiednim kodem

## Uruchomienie

1. Skompiluj kod: `forge build`
2. Uruchom testy: `forge test -vvvv` (czym więcej 'v' tym bardziej szczegółowe logowanie)

## Attributions

toHex() function taken from Mikhail Vladimirov, published on GitHub: https://stackoverflow.com/questions/67893318/solidity-how-to-represent-bytes32-as-string
