FROM node:18.20.2-alpine AS builder
WORKDIR /app
COPY ./package.json .
COPY ./yarn.lock .

RUN yarn install
COPY . .
RUN yarn build

FROM nginx:stable-alpine
WORKDIR /usr/share/nginx/html
RUN rm -rf ./*
COPY --from=builder /app/dist .
EXPOSE 80
ENTRYPOINT ["nginx", "-g", "daemon off;"]