pipeline {
    agent any

    environment {
        DOCKER_IMAGE = "jaspsing369/petclinic"
    }

    triggers {
        githubPush()
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build JAR (Maven)') {
            steps {
                sh 'mvn clean package -DskipTests -Dcheckstyle.skip=true'

            }
        }

        stage('Docker Build') {
            steps {
                script {
                    COMMIT = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()

                    sh """
                    docker build \
                      -t ${DOCKER_IMAGE}:latest \
                      -t ${DOCKER_IMAGE}:${COMMIT} .
                    """
                }
            }
        }

        stage('Docker Push') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'USER',
                    passwordVariable: 'PASS'
                )]) {
                    sh """
                    echo "$PASS" | docker login -u "$USER" --password-stdin
                    docker push ${DOCKER_IMAGE}:latest
                    docker push ${DOCKER_IMAGE}:${COMMIT}
                    """
                }
            }
        }
        stage('Terraform Init') {
            steps {
                dir('terraform') {
                    withCredentials([
                        string(credentialsId: 'aws-access-key', variable: 'AWS_ACCESS_KEY_ID'),
                        string(credentialsId: 'aws-secret-key', variable: 'AWS_SECRET_ACCESS_KEY')
                    ]) {
                        sh "terraform init"
                    }
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                dir('terraform') {
                withCredentials([
                    sshUserPrivateKey(credentialsId: 'aws-ssh-key', keyFileVariable: 'SSH_KEY_PATH'),
                    string(credentialsId: 'aws-access-key', variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws-secret-key', variable: 'AWS_SECRET_ACCESS_KEY')
                ]) {

                    sh '''
                    echo "Creating real SSH key file..."

                    # IMPORTANT: write PEM key into a real file that Jenkins will NOT mask
                    cp "$SSH_KEY_PATH" /tmp/real_aws_key.pem
                    chmod 600 /tmp/real_aws_key.pem

                    echo "Running Terraform..."
                    terraform apply -auto-approve \
                        -var key_name=test \
                        -var private_key_path="/tmp/real_aws_key.pem"
                    '''
                }


                }
            }
        }


    }

    post {
        always {
            sh 'docker logout || true'
        }
    }
}

