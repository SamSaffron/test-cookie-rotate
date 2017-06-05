FROM 'ruby:2.4.1'

run gem install puma rack

expose 80

add config.ru /src/config.ru
workdir /src/
cmd rackup -p 80 -o 0.0.0.0
